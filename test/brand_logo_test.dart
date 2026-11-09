import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets(
    'the phone header uses the mark and the wide header the full logo',
    (tester) async {
      await pumpScapeMatch(tester);
      expect(find.byType(ScapeLogo), findsOneWidget);
      expect(find.text('EscapeMatch'), findsNothing);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();

      expect(find.text('EscapeMatch'), findsOneWidget);
      final logo = tester.widget<ScapeLogo>(find.byType(ScapeLogo));
      expect(logo.variant, ScapeLogoVariant.full);
    },
  );

  testWidgets('the intro shows the full logo', (tester) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('EscapeMatch'), findsWidgets);
    expect(
      tester
          .widgetList<ScapeLogo>(find.byType(ScapeLogo))
          .every((logo) => logo.variant == ScapeLogoVariant.full),
      isTrue,
    );
  });

  testWidgets('wordmarkAbsorb holds the lockup, then trains into the pin', (
    tester,
  ) async {
    Future<void> pump(double absorb) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScapeLogo(
                height: 80,
                onDark: false,
                wordmarkAbsorb: absorb,
              ),
            ),
          ),
        ),
      );
    }

    Rect pinInLogo() {
      final origin = tester.getTopLeft(find.byType(ScapeLogo));
      return tester.getRect(find.byType(SvgPicture)).shift(-origin);
    }

    await pump(0);
    final pin = tester.getRect(find.byType(SvgPicture));
    final word = tester.getRect(find.text('EscapeMatch'));
    final box = tester.getRect(find.byType(ScapeLogo));
    expect(
      pin.width / pin.height,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.01),
    );
    expect(word.left, greaterThanOrEqualTo(pin.right - 1));
    expect(word.left, greaterThanOrEqualTo(box.left));
    expect(word.right, lessThanOrEqualTo(box.right));
    expect(pin.top, greaterThanOrEqualTo(box.top));
    expect(pin.bottom, lessThanOrEqualTo(box.bottom + 0.5));
    expect(
      find.descendant(
        of: find.byType(ScapeLogo),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
    );
    final held = pinInLogo();

    await pump(0.5);
    final movedPin = pinInLogo();
    final movedWord = tester.getRect(find.text('EscapeMatch'));
    expect(movedPin.width, closeTo(held.width, 0.5));
    expect(movedPin.height, closeTo(held.height, 0.5));
    expect(movedPin.left, closeTo(held.left, 0.5));
    expect(movedWord.left, lessThan(word.left));
    final clipFinder = find.descendant(
      of: find.byType(ScapeLogo),
      matching: find.byType(ClipPath),
    );
    expect(clipFinder, findsOneWidget);
    final clip = tester.getRect(clipFinder);
    final pinRect = tester.getRect(find.byType(SvgPicture));
    // A folga do viewBox (x=190..200) fica dentro do recorte. O ClipRect
    // antigo começava na borda da caixa e cortava as letras nessa faixa.
    expect(clip.left, lessThan(pinRect.right - 4));
    expect(movedWord.right, lessThanOrEqualTo(clip.right + 1));
    final path = tester
        .widget<ClipPath>(clipFinder)
        .clipper!
        .getClip(tester.getSize(clipFinder));
    final origin = tester.getTopLeft(clipFinder);
    Offset local(Offset global) => global - origin;
    expect(
      path.contains(
        local(
          Offset(
            pinRect.left + pinRect.width * 195 / 200,
            pinRect.top + pinRect.height * 100 / 260,
          ),
        ),
      ),
      isTrue,
    );
    expect(
      path.contains(
        local(
          Offset(
            pinRect.left + pinRect.width * 2 / 200,
            pinRect.top + pinRect.height * 100 / 260,
          ),
        ),
      ),
      isFalse,
    );

    await pump(1);
    expect(find.text('EscapeMatch'), findsNothing);
    final buried = tester.getRect(find.byType(SvgPicture));
    expect(
      buried.width / buried.height,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.01),
    );
    expect(buried.width, closeTo(pin.width, 0.5));
    expect(pinInLogo().left, closeTo(held.left, 0.5));
  });

  test('the player bundle keys the pin without the package prefix', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.getAssetVariants(ScapeLogo.markAsset), isNotNull);
    expect(manifest.getAssetVariants(ScapeLogo.markOnDarkAsset), isNotNull);
    expect(
      manifest.getAssetVariants(
        ScapePinLoader.packagedKey(ScapeLogo.markAsset),
      ),
      isNull,
    );
    expect(
      manifest.getAssetVariants(
        ScapePinLoader.packagedKey(ScapeLogo.markOnDarkAsset),
      ),
      isNull,
    );

    final loaded = await ScapePinLoader(ScapeLogo.markAsset).readSvg();
    final direct = await rootBundle.load(ScapeLogo.markAsset);
    expect(_bytes(loaded), _bytes(direct));
  });

  test('the pin loader prefers the shared package key', () async {
    const shared = '<svg id="shared"/>';
    const local = '<svg id="local"/>';
    final bundle = _MemoryBundle({
      ScapePinLoader.packagedKey(ScapeLogo.markAsset): shared,
      ScapeLogo.markAsset: local,
    });
    final bytes = await ScapePinLoader(
      ScapeLogo.markAsset,
      assetBundle: bundle,
    ).readSvg();
    expect(_text(bytes), shared);
  });

  test(
    'the pin loader uses the app key when the package key is absent',
    () async {
      const local = '<svg id="player"/>';
      final bundle = _MemoryBundle({ScapeLogo.markAsset: local});
      final bytes = await ScapePinLoader(
        ScapeLogo.markAsset,
        assetBundle: bundle,
      ).readSvg();
      expect(_text(bytes), local);
    },
  );

  test('the pin loader reports a missing svg', () async {
    final bundle = _MemoryBundle(const {});
    expect(
      ScapePinLoader(ScapeLogo.markAsset, assetBundle: bundle).readSvg(),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('the pin paints beside the wordmark in light and dark', (
    tester,
  ) async {
    await tester.runAsync(_loadPoppins);
    tester.view.physicalSize = const Size(800, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> expectInk(bool onDark, Color ink, String shot) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: const Color(0xFFFF00FF),
            child: Center(child: ScapeLogo(height: 96, onDark: onDark)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EscapeMatch'), findsOneWidget);
      final pin = tester.getRect(find.byType(SvgPicture));
      final word = tester.getRect(find.text('EscapeMatch'));
      expect(pin.width, greaterThan(20));
      expect(pin.height, closeTo(96, 0.5));
      expect(pin.right, lessThanOrEqualTo(word.left + 1));
      final image = await _capture(tester);
      final hits = await tester.runAsync(() => _countInk(image, pin, ink));
      expect(hits, greaterThan(40));
      await tester.runAsync(() => _saveShot(image, shot));
      image.dispose();
    }

    await expectInk(false, ScapeLogo.pin, 'logo-pin-light.png');
    await expectInk(true, ScapeLogo.pinOnDark, 'logo-pin-dark.png');
  });

  testWidgets('the train meets the green silhouette, not a white halo', (
    tester,
  ) async {
    await tester.runAsync(_loadPoppins);
    const height = 180.0;
    tester.view.physicalSize = const Size(980, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pump(double absorb, Color background) {
      return tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: background,
            body: Center(
              child: ScapeLogo(
                height: height,
                onDark: false,
                wordmarkAbsorb: absorb,
              ),
            ),
          ),
        ),
      );
    }

    await pump(0, const Color(0xFFFF00FF));
    await tester.pumpAndSettle();
    final barePin = tester.getRect(find.byType(SvgPicture));
    final magenta = await _capture(tester);
    final gutter = await tester.runAsync(
      () => _pixel(magenta, _viewBoxPoint(barePin, 197, 100)),
    );
    final disc = await tester.runAsync(
      () => _pixel(magenta, _viewBoxPoint(barePin, 46, 100)),
    );
    magenta.dispose();
    expect(gutter, isNotNull);
    expect(disc, isNotNull);
    expect(_nearMagenta(gutter!), isTrue, reason: '$gutter');
    expect(_nearWhite(disc!), isTrue, reason: '$disc');

    await pump(0, Colors.white);
    await tester.pumpAndSettle();
    final heldPin = tester.getRect(find.byType(SvgPicture));
    final heldWord = tester.getRect(find.text('EscapeMatch'));
    final heldLogo = tester.getRect(find.byType(ScapeLogo));
    final heldImage = await _capture(tester);
    final discBox = await tester.runAsync(() => _whiteDisc(heldImage, heldPin));
    expect(discBox, isNotNull);
    expect(discBox!.width / discBox.height, closeTo(1, 0.12));
    expect(discBox.height / heldPin.height, closeTo(128 / 260, 0.06));
    await tester.runAsync(
      () => _saveCrop(heldImage, heldLogo, 'splash-trem-hold.png'),
    );
    heldImage.dispose();

    final lane = heldLogo.width - heldPin.width;
    final greenRight = heldPin.left + heldPin.width * 190 / 200;
    final absorb =
        ((heldWord.right - (greenRight + heldWord.width * 0.32)) / lane).clamp(
          0.05,
          0.95,
        );
    await pump(absorb, Colors.white);
    await tester.pumpAndSettle();

    final clipFinder = find.descendant(
      of: find.byType(ScapeLogo),
      matching: find.byType(ClipPath),
    );
    final clipSize = tester.getSize(clipFinder);
    final path = tester.widget<ClipPath>(clipFinder).clipper!.getClip(clipSize);
    final pin = tester.getRect(find.byType(SvgPicture));
    final logo = tester.getRect(find.byType(ScapeLogo));
    expect(clipSize.height, closeTo(height, 0.5));
    expect(pin.width, closeTo(heldPin.width, 0.5));
    expect(
      pin.width / pin.height,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.01),
    );

    final equator = _leftBoundary(path, clipSize, height * 100 / 260);
    final taper = _leftBoundary(path, clipSize, height * 180 / 260);
    final pinW = pin.width;
    expect(equator, closeTo(pinW * 10 / 200 + 1, 2));
    expect(equator, lessThan(pinW * (100 - 64) / 200 - 4));
    final neckT = (180 - 154) / (250 - 154);
    final neckX = 28 + (100 - 28) * neckT;
    expect(taper, closeTo(pinW * neckX / 200 + 1, 2));
    expect(taper, greaterThan(equator + pinW * 0.08));

    final image = await _capture(tester);
    await tester.runAsync(() => _saveCrop(image, logo, 'splash-trem-meio.png'));
    final touch = await tester.runAsync(() => _orangeTouch(image, pin));
    final stray = await tester.runAsync(
      () => _orangeLeftOfPin(image, logo, pin),
    );
    expect(touch, greaterThan(12));
    // Uma letra vazada ocupa centenas de pixels. O fiapo é antialiasing.
    expect(stray, lessThan(40));
    final junction = Rect.fromLTRB(
      pin.left + pin.width * 0.72,
      pin.top + pin.height * 0.08,
      tester.getRect(find.text('EscapeMatch')).right + 8,
      pin.top + pin.height * 0.78,
    );
    await tester.runAsync(
      () => _saveCrop(image, junction, 'splash-trem-encontro.png', pad: 8),
    );
    image.dispose();
  });
}

Uint8List _bytes(ByteData data) => Uint8List.sublistView(data);

String _text(ByteData data) => String.fromCharCodes(_bytes(data));

class _MemoryBundle extends AssetBundle {
  _MemoryBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final value = files[key];
    if (value == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(value.codeUnits));
  }
}

Future<void> _loadPoppins() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
  await loader.load();
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>());
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size),
  );
  expect(image, isNotNull);
  return image!;
}

Future<int> _countInk(ui.Image image, Rect pin, Color ink) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    return 0;
  }
  final pixels = bytes.buffer.asUint8List();
  final red = (ink.r * 255.0).round();
  final green = (ink.g * 255.0).round();
  final blue = (ink.b * 255.0).round();
  final left = pin.left.floor().clamp(0, image.width - 1);
  final top = pin.top.floor().clamp(0, image.height - 1);
  final right = pin.right.ceil().clamp(0, image.width);
  final bottom = pin.bottom.ceil().clamp(0, image.height);
  var hits = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * image.width + x) * 4;
      if ((pixels[i] - red).abs() <= 8 &&
          (pixels[i + 1] - green).abs() <= 8 &&
          (pixels[i + 2] - blue).abs() <= 8) {
        hits++;
      }
    }
  }
  return hits;
}

Future<void> _saveShot(ui.Image image, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) {
    return;
  }
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Offset _viewBoxPoint(Rect pin, double vx, double vy) {
  return Offset(
    pin.left + pin.width * vx / ScapeLogo.markAspectWidth,
    pin.top + pin.height * vy / ScapeLogo.markAspectHeight,
  );
}

Future<List<int>> _pixel(ui.Image image, Offset point) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = bytes!.buffer.asUint8List();
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  final i = (y * image.width + x) * 4;
  return [pixels[i], pixels[i + 1], pixels[i + 2]];
}

bool _nearWhite(List<int> rgb) => rgb[0] > 242 && rgb[1] > 242 && rgb[2] > 242;

bool _nearMagenta(List<int> rgb) => rgb[0] > 240 && rgb[1] < 20 && rgb[2] > 240;

bool _isWhite(Uint8List pixels, int i) =>
    pixels[i] > 242 && pixels[i + 1] > 242 && pixels[i + 2] > 242;

bool _isGreen(Uint8List pixels, int i) {
  final red = pixels[i];
  final green = pixels[i + 1];
  final blue = pixels[i + 2];
  return (red - 15).abs() < 36 &&
      (green - 76).abs() < 36 &&
      (blue - 74).abs() < 36 &&
      green + 8 > red;
}

bool _isOrange(Uint8List pixels, int i) {
  final red = pixels[i];
  final green = pixels[i + 1];
  final blue = pixels[i + 2];
  return red > 160 && red > green + 30 && green > 40 && blue < 120;
}

double _leftBoundary(Path path, Size size, double y) {
  var lo = 0.0;
  var hi = size.width;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (path.contains(Offset(mid, y))) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

Future<Size?> _whiteDisc(ui.Image image, Rect pin) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    return null;
  }
  final pixels = bytes.buffer.asUint8List();
  final width = image.width;
  final left = pin.left.floor().clamp(0, width - 1);
  final top = pin.top.floor().clamp(0, image.height - 1);
  final right = pin.right.ceil().clamp(0, width);
  final bottom = pin.bottom.ceil().clamp(0, image.height);
  final span = right - left;
  if (span <= 0 || bottom <= top) {
    return null;
  }
  bool whiteAt(int x, int y) => _isWhite(pixels, (y * width + x) * 4);
  final seen = List<bool>.filled(span * (bottom - top), false);
  int at(int x, int y) => (y - top) * span + (x - left);
  final queue = <int>[];
  void push(int x, int y) {
    if (x < left || y < top || x >= right || y >= bottom) {
      return;
    }
    final index = at(x, y);
    if (seen[index] || !whiteAt(x, y)) {
      return;
    }
    seen[index] = true;
    queue.add(index);
  }

  for (var x = left; x < right; x++) {
    push(x, top);
    push(x, bottom - 1);
  }
  for (var y = top; y < bottom; y++) {
    push(left, y);
    push(right - 1, y);
  }
  var head = 0;
  while (head < queue.length) {
    final index = queue[head++];
    final x = left + index % span;
    final y = top + index ~/ span;
    push(x - 1, y);
    push(x + 1, y);
    push(x, y - 1);
    push(x, y + 1);
  }

  var minX = right;
  var minY = bottom;
  var maxX = left;
  var maxY = top;
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      if (!whiteAt(x, y) || seen[at(x, y)]) {
        continue;
      }
      count++;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (count < 20) {
    return null;
  }
  return Size((maxX - minX + 1).toDouble(), (maxY - minY + 1).toDouble());
}

Future<int> _orangeTouch(ui.Image image, Rect pin) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    return 0;
  }
  final pixels = bytes.buffer.asUint8List();
  final width = image.width;
  final left = pin.left.floor().clamp(0, width - 1);
  final top = pin.top.floor().clamp(0, image.height - 1);
  final right = pin.right.ceil().clamp(0, width);
  final bottom = pin.bottom.ceil().clamp(0, image.height);
  final zoneLeft = left + ((right - left) * 0.70).floor();
  var touching = 0;
  for (var y = top; y < bottom; y++) {
    int? edge;
    for (var x = right - 1; x >= zoneLeft; x--) {
      if (_isGreen(pixels, (y * width + x) * 4)) {
        edge = x;
        break;
      }
    }
    if (edge == null) {
      continue;
    }
    var gap = 0;
    var found = false;
    final limit = edge + 24 < width ? edge + 24 : width - 1;
    for (var x = edge + 1; x <= limit; x++) {
      final i = (y * width + x) * 4;
      if (_isOrange(pixels, i)) {
        found = true;
        break;
      }
      if (_isWhite(pixels, i)) {
        gap++;
      }
    }
    if (found && gap <= 2) {
      touching++;
    }
  }
  return touching;
}

Future<int> _orangeLeftOfPin(ui.Image image, Rect logo, Rect pin) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    return 0;
  }
  final pixels = bytes.buffer.asUint8List();
  final width = image.width;
  final left = pin.left.floor().clamp(0, width - 1);
  final top = pin.top.floor().clamp(0, image.height - 1);
  final right = pin.right.ceil().clamp(0, width);
  final bottom = pin.bottom.ceil().clamp(0, image.height);
  final logoLeft = logo.left.floor().clamp(0, width - 1);
  var stray = 0;
  for (var y = top; y < bottom; y++) {
    int? edge;
    for (var x = left; x < right; x++) {
      if (_isGreen(pixels, (y * width + x) * 4)) {
        edge = x;
        break;
      }
    }
    if (edge == null) {
      continue;
    }
    final stop = edge - 4;
    for (var x = logoLeft; x < stop; x++) {
      if (!_isWhite(pixels, (y * width + x) * 4)) {
        stray++;
      }
    }
  }
  return stray;
}

Future<void> _saveCrop(
  ui.Image image,
  Rect source,
  String name, {
  double pad = 16,
}) async {
  final left = (source.left - pad).clamp(0.0, image.width - 1.0);
  final top = (source.top - pad).clamp(0.0, image.height - 1.0);
  final right = (source.right + pad).clamp(left + 1, image.width.toDouble());
  final bottom = (source.bottom + pad).clamp(top + 1, image.height.toDouble());
  final src = Rect.fromLTRB(
    left.floorToDouble(),
    top.floorToDouble(),
    right.ceilToDouble(),
    bottom.ceilToDouble(),
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, src.width, src.height),
    Paint(),
  );
  final cropped = await recorder.endRecording().toImage(
    src.width.ceil(),
    src.height.ceil(),
  );
  await _saveShot(cropped, name);
  cropped.dispose();
}
