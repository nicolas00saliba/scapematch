import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';

/// Enquadramento da foto dentro da moldura.
///
/// [scale] 1 cobre a moldura (como `BoxFit.cover`). Abaixo de 1 sobra faixa.
/// [panX] e [panY] vão de -1 a 1 ao longo da folga.
class FramePlacement {
  const FramePlacement({this.scale = 1, this.panX = 0, this.panY = 0});

  final double scale;
  final double panX;
  final double panY;

  FramePlacement copyWith({double? scale, double? panX, double? panY}) {
    return FramePlacement(
      scale: scale ?? this.scale,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
    );
  }
}

/// Retângulo da foto, em pixels da moldura.
Rect placedRect({
  required int imageWidth,
  required int imageHeight,
  required int frameWidth,
  required int frameHeight,
  required FramePlacement placement,
}) {
  final cover = math.max(frameWidth / imageWidth, frameHeight / imageHeight);
  final drawW = imageWidth * cover * placement.scale;
  final drawH = imageHeight * cover * placement.scale;
  final minLeft = math.min(0, frameWidth - drawW);
  final maxLeft = math.max(0.0, frameWidth - drawW);
  final minTop = math.min(0, frameHeight - drawH);
  final maxTop = math.max(0.0, frameHeight - drawH);
  final panX = placement.panX.clamp(-1.0, 1.0);
  final panY = placement.panY.clamp(-1.0, 1.0);
  final left = minLeft + (panX + 1) / 2 * (maxLeft - minLeft);
  final top = minTop + (panY + 1) / 2 * (maxTop - minTop);
  return Rect.fromLTWH(left, top, drawW, drawH);
}

/// Escala em que a foto inteira cabe na moldura, relativa ao cover.
double containScale({
  required int imageWidth,
  required int imageHeight,
  required int frameWidth,
  required int frameHeight,
}) {
  final cover = math.max(frameWidth / imageWidth, frameHeight / imageHeight);
  final contain = math.min(frameWidth / imageWidth, frameHeight / imageHeight);
  if (cover == 0) {
    return 1;
  }
  return contain / cover;
}

bool frameNeedsExpansion({
  required int imageWidth,
  required int imageHeight,
  required RoomFrame frame,
}) {
  final scale = containScale(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    frameWidth: frame.width,
    frameHeight: frame.height,
  );
  return scale < 0.98;
}

Future<ui.Image> decodePhoto(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Redesenha [source] num retângulo, sem moldura em volta.
Future<Uint8List> renderImageBox({
  required ui.Image source,
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint(),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await encodePng(image);
  image.dispose();
  return bytes;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Desenha [source] na moldura. O resultado tem exatamente o tamanho dela.
Future<Uint8List> renderRoomFrame({
  required ui.Image source,
  required RoomFrame frame,
  required FramePlacement placement,
}) {
  return _render(
    source: source,
    width: frame.width,
    height: frame.height,
    placement: placement,
    fillGaps: false,
  );
}

/// Preenche as faixas com a própria foto ampliada e desfocada.
///
/// É a expansão simulada: não chama rede e não inventa um cenário novo.
Future<Uint8List> simulateSceneFill({
  required ui.Image source,
  required RoomFrame frame,
}) {
  final scale = containScale(
    imageWidth: source.width,
    imageHeight: source.height,
    frameWidth: frame.width,
    frameHeight: frame.height,
  );
  return _render(
    source: source,
    width: frame.width,
    height: frame.height,
    placement: FramePlacement(scale: scale),
    fillGaps: true,
  );
}

Future<Uint8List> _render({
  required ui.Image source,
  required int width,
  required int height,
  required FramePlacement placement,
  required bool fillGaps,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(bounds, Paint()..color = const Color(0xFF1C1917));
  final src = Rect.fromLTWH(
    0,
    0,
    source.width.toDouble(),
    source.height.toDouble(),
  );
  if (fillGaps) {
    final cover = placedRect(
      imageWidth: source.width,
      imageHeight: source.height,
      frameWidth: width,
      frameHeight: height,
      placement: const FramePlacement(),
    );
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImageRect(source, src, cover, Paint());
    canvas.restore();
  }
  final dest = placedRect(
    imageWidth: source.width,
    imageHeight: source.height,
    frameWidth: width,
    frameHeight: height,
    placement: placement,
  );
  canvas.drawImageRect(source, src, dest, Paint());
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await encodePng(image);
  image.dispose();
  return bytes;
}
