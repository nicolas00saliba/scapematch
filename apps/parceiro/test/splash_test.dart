import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('a phone cold start shows the partner logo at the pin size', (
    tester,
  ) async {
    await tester.runAsync(_loadPoppins);
    await pumpParceiro(tester, size: const Size(390, 844), settle: false);
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    final logo = _splashLogo(tester);
    expect(logo.variant, ScapeLogoVariant.full);
    expect(logo.wordmarkAbsorb, 0);
    expect(logo.onDark, isTrue);
    final mark = logo.markImage;
    expect(mark, isA<AssetImage>());
    expect(
      (mark! as AssetImage).assetName,
      'assets/parceiro/logo_parceiro_pin.png',
    );

    final pin = find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(Image),
    );
    expect(pin, findsOneWidget);
    expect(
      tester.getSize(pin).aspectRatio,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.001),
    );

    await tester.runAsync(() async {
      await precacheImage(mark, tester.element(pin));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    _expectBlackCurtain(tester);
    _expectLightWordmark(tester);

    var elapsed = 0;
    Future<void> pumpTo(double t) async {
      final target = (SplashGate.duration.inMilliseconds * t).round();
      await tester.pump(Duration(milliseconds: target - elapsed));
      elapsed = target;
    }

    await pumpTo(SplashGate.holdEnd);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
    _expectBlackCurtain(tester);
    _expectLightWordmark(tester);
    await _saveSplashShot(tester, 'parceiro-splash-hold.png');

    await pumpTo(0.46);
    expect(_splashLogo(tester).wordmarkAbsorb, inExclusiveRange(0, 1));
    _expectBlackCurtain(tester);
    await _saveSplashShot(tester, 'parceiro-splash-trem.png');

    await pumpTo(0.80);
    expect(_splashLogo(tester).wordmarkAbsorb, 1);
    expect(find.text('ScapeMatch'), findsNothing);
    _expectBlackCurtain(tester);
    await _saveSplashShot(tester, 'parceiro-splash-giro.png');

    await pumpTo(1);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
  });

  testWidgets('reduced motion stays a short fade without the spin', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpParceiro(tester, size: const Size(390, 844), settle: false);
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
    expect(_splashLogo(tester).onDark, isTrue);
    _expectBlackCurtain(tester);
    _expectLightWordmark(tester);
    expect(SplashGate.reducedDuration, const Duration(milliseconds: 180));

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(AppKeys.splash), findsOneWidget);

    await tester.pump(SplashGate.reducedDuration);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
  });

  testWidgets('the site width skips the splash', (tester) async {
    await pumpParceiro(tester, size: const Size(1280, 800), settle: false);
    expect(find.byKey(AppKeys.splash), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

ScapeLogo _splashLogo(WidgetTester tester) {
  return tester.widget<ScapeLogo>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(ScapeLogo),
    ),
  );
}

void _expectBlackCurtain(WidgetTester tester) {
  expect(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == ScapeLogo.markImageBackground,
      ),
    ),
    findsOneWidget,
  );
}

void _expectLightWordmark(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.text('ScapeMatch'),
    ),
  );
  final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
  expect(spans.first.style!.color, ScapeLogo.pinOnDark);
  expect(spans.last.style!.color, ScapeLogo.copper);
}

Future<void> _loadPoppins() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
  await loader.load();
}

Future<void> _saveSplashShot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) {
    return;
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>());
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}
