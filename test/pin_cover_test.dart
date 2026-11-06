import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('player and partner use the same padded pin icons', () async {
    const shared = [
      'favicon.png',
      'icons/Icon-192.png',
      'icons/Icon-512.png',
      'icons/Icon-maskable-192.png',
      'icons/Icon-maskable-512.png',
    ];
    for (final name in shared) {
      final player = File('web/$name').readAsBytesSync();
      final partner = File('apps/parceiro/web/$name').readAsBytesSync();
      expect(partner, player, reason: name);
    }

    await _expectPin(
      'web/icons/Icon-512.png',
      maskable: false,
      roundDisk: true,
    );
    await _expectPin('web/icons/Icon-192.png', maskable: false);
    await _expectPin('web/favicon.png', maskable: false);
    await _expectPin('web/icons/Icon-maskable-512.png', maskable: true);
    await _expectPin('web/icons/Icon-maskable-192.png', maskable: true);
    await _expectPin(
      'assets/brand/pin_capa.jpg',
      maskable: false,
      roundDisk: true,
    );
  });
}

Future<void> _expectPin(
  String path, {
  required bool maskable,
  bool roundDisk = false,
}) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final width = image.width;
  final height = image.height;
  expect(width, height, reason: path);

  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;
  var found = false;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (_isBackground(data, width, x, y)) {
        continue;
      }
      found = true;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }
  expect(found, isTrue, reason: path);
  final contentW = maxX - minX + 1;
  final contentH = maxY - minY + 1;
  expect(
    contentW / contentH,
    closeTo(180 / 240, 0.04),
    reason: '$path stretched the pin',
  );

  if (maskable) {
    final radius = width * 0.40;
    final center = (width - 1) / 2;
    for (final point in [
      (minX, minY),
      (maxX, minY),
      (minX, maxY),
      (maxX, maxY),
    ]) {
      final dx = point.$1 - center;
      final dy = point.$2 - center;
      expect(
        dx * dx + dy * dy,
        lessThanOrEqualTo(radius * radius),
        reason: '$path leaves the maskable safe circle',
      );
    }
  } else {
    final margin = math.min(
      math.min(minX, minY),
      math.min(width - 1 - maxX, height - 1 - maxY),
    );
    expect(margin / width, greaterThanOrEqualTo(0.08), reason: path);
  }

  if (roundDisk) {
    final scaleX = contentW / 180;
    final centerX = (minX + 90 * scaleX).round();
    final centerY = (minY + 90 * (contentH / 240)).round();
    final east = _radiusUntilTeal(data, width, height, centerX, centerY, 1, 0);
    final north = _radiusUntilTeal(
      data,
      width,
      height,
      centerX,
      centerY,
      0,
      -1,
    );
    expect((east - north).abs(), lessThanOrEqualTo(3), reason: path);
    expect(east, closeTo(64 * scaleX, 4), reason: path);
  }
  image.dispose();
}

bool _isBackground(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return data.getUint8(i) >= 246 &&
      data.getUint8(i + 1) >= 246 &&
      data.getUint8(i + 2) >= 246;
}

bool _isTeal(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  final r = data.getUint8(i);
  final g = data.getUint8(i + 1);
  final b = data.getUint8(i + 2);
  return r < 90 && g > 40 && b > 40 && g > r + 15;
}

int _radiusUntilTeal(
  ByteData data,
  int width,
  int height,
  int cx,
  int cy,
  int dx,
  int dy,
) {
  var x = cx;
  var y = cy;
  for (var step = 1; step < width; step++) {
    x += dx;
    y += dy;
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return step;
    }
    if (_isTeal(data, width, x, y)) {
      return step - 1;
    }
  }
  return 0;
}
