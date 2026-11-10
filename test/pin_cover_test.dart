import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('player pin icons keep the padded white cover', () async {
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

  test('partner icons use the black logo in the player frame', () async {
    const shared = [
      'favicon.png',
      'icons/Icon-192.png',
      'icons/Icon-512.png',
      'icons/Icon-maskable-192.png',
      'icons/Icon-maskable-512.png',
    ];
    final source = await _decode(
      'apps/parceiro/assets/parceiro/logo_parceiro.png',
    );
    expect(source.image.width, 816);
    expect(source.image.height, 1062);
    expect(_pixel(source, 0, 0), (17, 17, 17, 255));
    expect(_pixel(source, 815, 1061), (17, 17, 17, 255));
    final sourceBox = _bounds(source, _isPartnerBlack);

    for (final name in shared) {
      final playerBytes = File('web/$name').readAsBytesSync();
      final partnerBytes = File('apps/parceiro/web/$name').readAsBytesSync();
      expect(partnerBytes, isNot(equals(playerBytes)), reason: name);

      final player = await _decodeBytes(playerBytes);
      final partner = await _decodeBytes(partnerBytes);
      expect(partner.image.width, player.image.width, reason: name);
      expect(partner.image.height, player.image.height, reason: name);
      expect(_pixel(partner, 0, 0), (17, 17, 17, 255), reason: name);
      expect(
        _pixel(partner, partner.image.width - 1, partner.image.height - 1),
        (17, 17, 17, 255),
        reason: name,
      );

      final playerBox = _bounds(player, _isWhiteBackground);
      final partnerBox = _bounds(partner, _isPartnerBlack);
      expect((partnerBox.minX - playerBox.minX).abs(), lessThanOrEqualTo(2));
      expect((partnerBox.minY - playerBox.minY).abs(), lessThanOrEqualTo(2));
      expect(
        (partnerBox.width - playerBox.width).abs(),
        lessThanOrEqualTo(2),
        reason: name,
      );
      expect(
        (partnerBox.height - playerBox.height).abs(),
        lessThanOrEqualTo(2),
        reason: name,
      );
      expect(
        partnerBox.width / partnerBox.height,
        closeTo(180 / 240, 0.04),
        reason: name,
      );

      final maskable = name.contains('maskable');
      if (maskable) {
        _expectInsideSafeCircle(partner, partnerBox, name);
      } else {
        final margin = [
          partnerBox.minX,
          partnerBox.minY,
          partner.image.width - 1 - partnerBox.maxX,
          partner.image.height - 1 - partnerBox.maxY,
        ].reduce(math.min);
        expect(
          margin / partner.image.width,
          greaterThanOrEqualTo(0.08),
          reason: name,
        );
      }

      final teal = _bounds(
        partner,
        (decoded, x, y) => !_isTealPixel(decoded, x, y),
      );
      expect(
        (teal.width - teal.height).abs(),
        lessThanOrEqualTo(2),
        reason: '$name stretched the disk',
      );

      if (partner.image.width >= 192) {
        final error = _artError(source, sourceBox, partner, partnerBox);
        final limit = partner.image.width >= 512 ? 3.0 : 12.0;
        expect(error, lessThanOrEqualTo(limit), reason: name);
      }

      player.image.dispose();
      partner.image.dispose();
    }
    source.image.dispose();
  });

  test(
    'the partner splash pin is the same art without the black square',
    () async {
      final source = await _decode(
        'apps/parceiro/assets/parceiro/logo_parceiro.png',
      );
      final pin = await _decode(
        'apps/parceiro/assets/parceiro/logo_parceiro_pin.png',
      );
      expect(pin.image.width, source.image.width);
      expect(pin.image.height, source.image.height);
      expect(_pixel(pin, 0, 0).$4, 0);
      expect(_pixel(pin, pin.image.width - 1, pin.image.height - 1).$4, 0);

      final width = pin.image.width;
      final height = pin.image.height;
      var mismatches = 0;
      var darkRim = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = _pixel(pin, x, y);
          final origin = _pixel(source, x, y);
          final alpha = pixel.$4;
          if (alpha == 255) {
            if (pixel.$1 != origin.$1 ||
                pixel.$2 != origin.$2 ||
                pixel.$3 != origin.$3) {
              mismatches++;
            }
            continue;
          }
          final neutral =
              (pixel.$1 - pixel.$2).abs() <= 2 &&
              (pixel.$2 - pixel.$3).abs() <= 2;
          final dark = math.max(pixel.$1, math.max(pixel.$2, pixel.$3)) < 80;
          if (alpha > 200 && neutral && dark) {
            darkRim++;
          }
          if (alpha > 0 && alpha < 255) {
            final scale = 255 / alpha;
            final red = (pixel.$1 * scale).round();
            final green = (pixel.$2 * scale).round();
            final blue = (pixel.$3 * scale).round();
            if (red < 248 || green < 248 || blue < 248) {
              mismatches++;
            }
          }
        }
      }
      expect(mismatches, 0);
      expect(darkRim, 0);
      source.image.dispose();
      pin.image.dispose();
    },
  );

  test('partner launch colors match the black splash', () {
    final partner = jsonDecode(
      File('apps/parceiro/web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(partner['background_color'], '#111111');
    expect(partner['theme_color'], '#111111');
    expect(partner['name'], 'EscapeMatch Parceiro');
    expect(partner['short_name'], 'Parceiro');
    expect(partner['id'], '/');
    expect(partner['start_url'], '/');
    expect(partner['scope'], '/');

    final html = File('apps/parceiro/web/index.html').readAsStringSync();
    expect(html, contains('content="#111111"'));
    expect(html, contains('background: #111111'));

    final player = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(player['background_color'], '#FFFFFF');
    expect(player['theme_color'], '#0F4C4A');
    expect(player['name'], 'EscapeMatch');
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

class _Raster {
  _Raster(this.image, this.data);

  final ui.Image image;
  final ByteData data;
}

class _Box {
  _Box(this.minX, this.minY, this.maxX, this.maxY);

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
}

Future<_Raster> _decode(String path) {
  return _decodeBytes(File(path).readAsBytesSync());
}

Future<_Raster> _decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return _Raster(image, data);
}

(int, int, int, int) _pixel(_Raster raster, int x, int y) {
  final i = (y * raster.image.width + x) * 4;
  final data = raster.data;
  return (
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
    data.getUint8(i + 3),
  );
}

bool _isPartnerBlack(_Raster raster, int x, int y) {
  final pixel = _pixel(raster, x, y);
  return pixel.$4 == 255 &&
      (pixel.$1 - 17).abs() <= 24 &&
      (pixel.$2 - 17).abs() <= 24 &&
      (pixel.$3 - 17).abs() <= 24;
}

bool _isWhiteBackground(_Raster raster, int x, int y) {
  final pixel = _pixel(raster, x, y);
  return pixel.$1 >= 246 && pixel.$2 >= 246 && pixel.$3 >= 246;
}

bool _isTealPixel(_Raster raster, int x, int y) {
  final pixel = _pixel(raster, x, y);
  return pixel.$1 < 90 &&
      pixel.$2 > 40 &&
      pixel.$3 > 40 &&
      pixel.$2 > pixel.$1 + 15;
}

_Box _bounds(
  _Raster raster,
  bool Function(_Raster raster, int x, int y) background,
) {
  final width = raster.image.width;
  final height = raster.image.height;
  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;
  var found = false;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (background(raster, x, y)) {
        continue;
      }
      found = true;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }
  expect(found, isTrue);
  return _Box(minX, minY, maxX, maxY);
}

void _expectInsideSafeCircle(_Raster raster, _Box box, String name) {
  final width = raster.image.width;
  final radius = width * 0.40;
  final center = (width - 1) / 2;
  for (final point in [
    (box.minX, box.minY),
    (box.maxX, box.minY),
    (box.minX, box.maxY),
    (box.maxX, box.maxY),
  ]) {
    final dx = point.$1 - center;
    final dy = point.$2 - center;
    expect(
      dx * dx + dy * dy,
      lessThanOrEqualTo(radius * radius),
      reason: '$name leaves the maskable safe circle',
    );
  }
}

double _artError(_Raster source, _Box sourceBox, _Raster icon, _Box iconBox) {
  var sum = 0.0;
  var count = 0;
  for (var gy = 0; gy < 20; gy++) {
    for (var gx = 0; gx < 16; gx++) {
      final sx = math.min(
        sourceBox.minX + sourceBox.width - 1,
        sourceBox.minX + ((gx + 0.5) / 16 * sourceBox.width).floor(),
      );
      final sy = math.min(
        sourceBox.minY + sourceBox.height - 1,
        sourceBox.minY + ((gy + 0.5) / 20 * sourceBox.height).floor(),
      );
      final ix = math.min(
        iconBox.minX + iconBox.width - 1,
        iconBox.minX + ((gx + 0.5) / 16 * iconBox.width).floor(),
      );
      final iy = math.min(
        iconBox.minY + iconBox.height - 1,
        iconBox.minY + ((gy + 0.5) / 20 * iconBox.height).floor(),
      );
      final origin = _pixel(source, sx, sy);
      final sample = _pixel(icon, ix, iy);
      sum += math.max(
        (origin.$1 - sample.$1).abs(),
        math.max((origin.$2 - sample.$2).abs(), (origin.$3 - sample.$3).abs()),
      );
      count++;
    }
  }
  return sum / count;
}
