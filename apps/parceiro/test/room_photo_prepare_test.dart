import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scapematch_parceiro/features/partner/data/room_photo_prepare.dart';

void main() {
  test('uma foto grande vira JPEG de no máximo 2048 px', () async {
    final jpeg = await prepareRoomPhoto(_png(width: 2500, height: 1000));

    expect(jpeg.length, greaterThan(2));
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);
    expect(jpeg.length, lessThan(10 * 1024 * 1024));
    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded!.width, 2048);
    expect(decoded.height, 819);
  });

  test('uma foto pequena não aumenta', () async {
    final small = await prepareRoomPhoto(_png(width: 40, height: 30));
    final decoded = img.decodeJpg(small);
    expect(decoded, isNotNull);
    expect(decoded!.width, 40);
    expect(decoded.height, 30);

    final exact = await prepareRoomPhoto(_png(width: 2048, height: 10));
    final kept = img.decodeJpg(exact);
    expect(kept, isNotNull);
    expect(kept!.width, 2048);
    expect(kept.height, 10);
  });

  test('bytes inválidos geram o erro amigável', () async {
    expect(
      prepareRoomPhoto(Uint8List.fromList(const [1, 2, 3, 4, 5])),
      throwsA(
        isA<RoomPhotoReadException>().having(
          (error) => error.message,
          'message',
          'Não consegui abrir esta foto. Tente uma foto JPG ou PNG.',
        ),
      ),
    );
  });

  test('a orientação EXIF entra nos pixels e a localização sai', () async {
    const secret = 'SEGREDO-GPS-25.4284-49.2733';
    final source = img.Image(width: 64, height: 32);
    img.fill(source, color: img.ColorRgb8(10, 40, 200));
    img.fillRect(
      source,
      x1: 0,
      y1: 0,
      x2: 15,
      y2: 15,
      color: img.ColorRgb8(220, 10, 10),
    );
    final plain = img.encodeJpg(source, quality: 95);
    final exif = img.ExifData();
    exif.imageIfd.orientation = 6;
    exif.imageIfd.imageDescription = secret;
    exif.gpsIfd.gpsLatitudeRef = 'S';
    final oriented = img.injectJpgExif(plain, exif);
    expect(oriented, isNotNull);
    expect(img.decodeJpgExif(oriented!), isNotNull);
    expect(_hasAscii(oriented, secret), isTrue);

    final jpeg = await prepareRoomPhoto(oriented);
    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    expect(decoded!.width, 32);
    expect(decoded.height, 64);
    final red = decoded.getPixel(23, 8);
    final blue = decoded.getPixel(4, 50);
    expect(red.r, greaterThan(red.b));
    expect(blue.b, greaterThan(blue.r));
    expect(img.decodeJpgExif(jpeg), isNull);
    expect(_hasAscii(jpeg, secret), isFalse);
  });

  test('se ainda passar do limite, a foto encolhe até caber', () async {
    final noisy = img.Image(width: 180, height: 180);
    img.fill(noisy, color: img.ColorRgb8(128, 128, 128));
    img.noise(noisy, 80, random: Random(7));
    final bytes = img.encodePng(noisy);
    final loose = await prepareRoomPhoto(bytes);
    expect(loose.length, greaterThan(4000));
    final cap = loose.length ~/ 3;
    final tight = await prepareRoomPhoto(bytes, maxBytes: cap);
    final decoded = img.decodeJpg(tight);
    expect(decoded, isNotNull);
    expect(tight.length, lessThan(cap));
    expect(decoded!.width, lessThanOrEqualTo(180));
    expect(decoded.height, lessThanOrEqualTo(180));
    expect(max(decoded.width, decoded.height), lessThanOrEqualTo(2048));
  });

  test('uma foto ilegível não impede as outras', () async {
    final batch = await prepareRoomPhotos([
      _png(width: 20, height: 12),
      Uint8List.fromList(const [9, 8, 7, 6]),
      _png(width: 8, height: 18),
    ]);
    expect(batch.photos, hasLength(2));
    expect(
      batch.error,
      'Não consegui abrir esta foto. Tente uma foto JPG ou PNG.',
    );
    expect(img.decodeJpg(batch.photos[0])!.height, 12);
    expect(img.decodeJpg(batch.photos[1])!.width, 8);
  });
}

bool _hasAscii(Uint8List bytes, String text) {
  final needle = text.codeUnits;
  if (needle.isEmpty || bytes.length < needle.length) return false;
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return true;
  }
  return false;
}

Uint8List _png({required int width, required int height, img.Color? color}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgb8(30, 90, 140));
  return img.encodePng(image);
}
