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
      expect(find.text('ScapeMatch'), findsNothing);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();

      expect(find.text('ScapeMatch'), findsOneWidget);
      final logo = tester.widget<ScapeLogo>(find.byType(ScapeLogo));
      expect(logo.variant, ScapeLogoVariant.full);
    },
  );

  testWidgets('the intro shows the full logo', (tester) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('ScapeMatch'), findsWidgets);
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
    final word = tester.getRect(find.text('ScapeMatch'));
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
    final movedWord = tester.getRect(find.text('ScapeMatch'));
    expect(movedPin.width, closeTo(held.width, 0.5));
    expect(movedPin.height, closeTo(held.height, 0.5));
    expect(movedPin.left, closeTo(held.left, 0.5));
    expect(movedWord.left, lessThan(word.left));
    final clip = tester.getRect(
      find.descendant(
        of: find.byType(ScapeLogo),
        matching: find.byType(ClipRect),
      ),
    );
    expect(
      clip.left,
      closeTo(tester.getRect(find.byType(SvgPicture)).right, 1),
    );
    expect(movedWord.right, lessThanOrEqualTo(clip.right + 1));

    await pump(1);
    expect(find.text('ScapeMatch'), findsNothing);
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
      expect(find.text('ScapeMatch'), findsOneWidget);
      final pin = tester.getRect(find.byType(SvgPicture));
      final word = tester.getRect(find.text('ScapeMatch'));
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
