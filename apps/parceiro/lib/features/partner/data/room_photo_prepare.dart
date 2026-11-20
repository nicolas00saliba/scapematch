import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Maior lado enviado ao bucket `room-photos`.
const roomPhotoMaxSide = 2048;

/// Qualidade JPEG inicial. Cai se o arquivo ainda passar do limite.
const roomPhotoJpegQuality = 85;

/// Teto do bucket proposto no PR #169 (10 MB).
const roomPhotoMaxBytes = 10 * 1024 * 1024;

/// Teto de pixels na abertura. 16k×16k cabe no padrão da biblioteca (~1 GB)
/// e fica de fora deste limite.
const roomPhotoMaxPixels = 50000000;

/// Foto que o codificador não conseguiu abrir.
class RoomPhotoReadException implements Exception {
  const RoomPhotoReadException([this.message = messageText]);

  static const messageText =
      'Não consegui abrir esta foto. Tente uma foto JPG ou PNG.';

  final String message;

  @override
  String toString() => message;
}

/// Fotos já em JPEG e, se alguma falhou, o aviso para a casa.
class RoomPhotoPick {
  const RoomPhotoPick(this.photos, {this.error});

  final List<Uint8List> photos;
  final String? error;
}

/// Decodifica, respeita a orientação, limita o lado e devolve JPEG sem EXIF.
Future<Uint8List> prepareRoomPhoto(
  Uint8List bytes, {
  int maxBytes = roomPhotoMaxBytes,
}) async {
  final prepared = await compute(_prepareRoomPhoto, (
    bytes: bytes,
    maxBytes: maxBytes,
  ), debugLabel: 'prepareRoomPhoto');
  final jpeg = prepared.jpeg;
  if (jpeg == null) {
    throw RoomPhotoReadException(
      prepared.error ?? RoomPhotoReadException.messageText,
    );
  }
  return jpeg;
}

/// Prepara cada arquivo. Uma foto ilegível não descarta as outras.
Future<RoomPhotoPick> prepareRoomPhotos(
  List<Uint8List> files, {
  int maxBytes = roomPhotoMaxBytes,
}) async {
  final photos = <Uint8List>[];
  String? error;
  for (final bytes in files) {
    if (bytes.isEmpty) {
      continue;
    }
    try {
      photos.add(await prepareRoomPhoto(bytes, maxBytes: maxBytes));
    } on RoomPhotoReadException catch (failure) {
      error ??= failure.message;
    }
  }
  return RoomPhotoPick(photos, error: error);
}

({Uint8List? jpeg, String? error}) _prepareRoomPhoto(
  ({Uint8List bytes, int maxBytes}) job,
) {
  try {
    return (jpeg: _encodeRoomPhoto(job.bytes, job.maxBytes), error: null);
  } on RoomPhotoReadException catch (error) {
    return (jpeg: null, error: error.message);
  }
}

Uint8List _encodeRoomPhoto(Uint8List bytes, int maxBytes) {
  final decoded = _decodeRoomPhoto(bytes);
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    throw const RoomPhotoReadException();
  }
  final fitted = _fitLongestSide(decoded, roomPhotoMaxSide);
  fitted.exif = img.ExifData();
  fitted.iccProfile = null;
  return _jpegUnder(fitted, maxBytes);
}

// decodeImage no image 4.13.1 só aceita frame. O teto de pixels é o
// estático que os decoders criados por essa função leem na construção.
img.Image? _decodeRoomPhoto(Uint8List bytes) {
  final previous = img.Decoder.defaultMaxPixels;
  img.Decoder.defaultMaxPixels = roomPhotoMaxPixels;
  try {
    return img.decodeImage(bytes, frame: 0);
  } on Object {
    return null;
  } finally {
    img.Decoder.defaultMaxPixels = previous;
  }
}

img.Image _fitLongestSide(img.Image image, int maxSide) {
  final orientation = image.exif.imageIfd.hasOrientation
      ? (image.exif.imageIfd.orientation ?? 1)
      : 1;
  final swaps = orientation >= 5 && orientation <= 8;
  final width = swaps ? image.height : image.width;
  final height = swaps ? image.width : image.height;
  final longest = width > height ? width : height;
  if (longest <= maxSide) {
    return img.bakeOrientation(image);
  }
  return img.copyResize(
    image,
    width: width >= height ? maxSide : null,
    height: height > width ? maxSide : null,
    interpolation: img.Interpolation.average,
  );
}

Uint8List _jpegUnder(img.Image image, int maxBytes) {
  var current = image;
  var quality = roomPhotoJpegQuality;
  var jpeg = img.encodeJpg(current, quality: quality);
  while (jpeg.length >= maxBytes) {
    if (quality > 50) {
      quality -= 15;
    } else if (current.width > 64 && current.height > 64) {
      final nextWidth = (current.width * 3) ~/ 4;
      final nextHeight = (current.height * 3) ~/ 4;
      current = img.copyResize(
        current,
        width: nextWidth,
        height: nextHeight,
        interpolation: img.Interpolation.average,
      );
      quality = roomPhotoJpegQuality;
    } else if (quality > 20) {
      quality -= 10;
    } else {
      break;
    }
    jpeg = img.encodeJpg(current, quality: quality);
  }
  if (jpeg.length >= maxBytes) {
    throw const RoomPhotoReadException();
  }
  return jpeg;
}
