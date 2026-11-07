import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

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
    _expectSealUnderLockup(tester);
    _expectPrintSeal(tester, find.byKey(PartnerSeal.splashKey));
    expect(_sealShift(tester), 0);
    final heldWord = tester.getRect(_splashWordmark(tester));
    final heldSeal = tester.getRect(_splashSeal(tester));
    await _saveSplashShot(tester, 'parceiro-splash-hold.png');

    await pumpTo(0.46);
    expect(_splashLogo(tester).wordmarkAbsorb, inExclusiveRange(0, 1));
    _expectBlackCurtain(tester);
    final trainingWord = tester.getRect(_splashWordmark(tester));
    final trainingSeal = tester.getRect(_splashSeal(tester));
    final pinRect = tester.getRect(_splashPin(tester));
    expect(trainingWord.left, lessThan(heldWord.left));
    expect(
      heldSeal.left - trainingSeal.left,
      closeTo(heldWord.left - trainingWord.left, 1),
    );
    expect(trainingSeal.center.dx, closeTo(pinRect.center.dx, 12));
    expect(trainingSeal.left, lessThan(pinRect.center.dx));
    expect(trainingSeal.right, greaterThan(pinRect.center.dx + 8));
    _expectSealClippedAtPin(tester, pinRect);
    await _saveSplashShot(tester, 'parceiro-splash-trem.png');

    await pumpTo(0.80);
    expect(_splashLogo(tester).wordmarkAbsorb, 1);
    expect(_splashWordmark(tester), findsNothing);
    expect(_splashSeal(tester), findsNothing);
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
    _expectSealUnderLockup(tester);
    _expectPrintSeal(tester, find.byKey(PartnerSeal.splashKey));
    expect(_sealShift(tester), 0);
    expect(SplashGate.reducedDuration, const Duration(milliseconds: 180));

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
    expect(_splashSeal(tester), findsOneWidget);
    expect(_sealShift(tester), 0);

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

Finder _splashWordmark(WidgetTester tester) {
  return find.descendant(
    of: find.byKey(AppKeys.splash),
    matching: find.text('ScapeMatch'),
  );
}

Finder _splashPin(WidgetTester tester) {
  return find.descendant(
    of: find.byKey(AppKeys.splash),
    matching: find.byType(Image),
  );
}

Finder _splashSeal(WidgetTester tester) {
  return find.descendant(
    of: find.byKey(AppKeys.splash),
    matching: find.byKey(PartnerSeal.splashKey),
  );
}

void _expectSealUnderLockup(WidgetTester tester) {
  final logo = tester.getRect(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(ScapeLogo),
    ),
  );
  final seal = tester.getRect(_splashSeal(tester));
  final slot = tester.getSize(find.byKey(PartnerSealTrain.slotKey));
  final extent = PartnerSealTrain.extentFor(
    tester.element(find.byKey(PartnerSealTrain.slotKey)),
    _splashLogo(tester).height,
  );
  expect(slot.height, closeTo(extent, 1));
  expect(seal.top, greaterThanOrEqualTo(logo.bottom - 1));
  expect(seal.center.dx, closeTo(logo.center.dx, 2));
  expect(
    seal.top - logo.bottom,
    closeTo(PartnerSeal.gapFor(_splashLogo(tester).height), 1),
  );
}

void _expectPrintSeal(WidgetTester tester, Finder seal) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: seal, matching: find.byType(DecoratedBox)),
  );
  final decoration = box.decoration as BoxDecoration;
  final border = decoration.border! as Border;
  expect(decoration.color, PartnerSeal.peach);
  expect(decoration.borderRadius, BorderRadius.circular(999));
  expect(border.top.width, PartnerSeal.borderWidth);
  expect(border.top.color, ScapeLogo.copper);
  final text = tester.widget<Text>(
    find.descendant(of: seal, matching: find.text(PartnerSeal.label)),
  );
  expect(text.style!.color, ScapeLogo.copper);
  expect(text.style!.fontWeight, FontWeight.w700);
}

void _expectSealClippedAtPin(WidgetTester tester, Rect pin) {
  final clipFinder = find.ancestor(
    of: find.byKey(PartnerSealTrain.trainKey),
    matching: find.byWidgetPredicate(
      (widget) => widget is ClipPath && widget.clipper is! ShapeBorderClipper,
    ),
  );
  expect(clipFinder, findsOneWidget);
  final clip = tester.widget<ClipPath>(clipFinder);
  expect(clip.clipBehavior, Clip.hardEdge);
  final path = clip.clipper!.getClip(tester.getSize(clipFinder));
  final origin = tester.getTopLeft(clipFinder);
  final seal = tester.getRect(_splashSeal(tester));
  Offset local(Offset global) => global - origin;
  expect(path.contains(local(seal.centerLeft + const Offset(1, 0))), isFalse);
  expect(path.contains(local(seal.centerRight + const Offset(-1, 0))), isTrue);
  final edge = origin.dx + path.getBounds().left;
  expect(edge - pin.center.dx, closeTo(1, 1.5));
}

double _sealShift(WidgetTester tester) {
  final train = tester.widget<Transform>(find.byKey(PartnerSealTrain.trainKey));
  return train.transform.getTranslation().x;
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
  await _loadRoboto();
}

Future<void> _loadRoboto() async {
  final roots = [
    Platform.environment['FLUTTER_ROOT'],
    '${Platform.environment['HOME']}/sdk/flutter',
    '/home/ubuntu/flutter',
    '/opt/flutter',
  ].whereType<String>();
  for (final root in roots) {
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (!dir.existsSync()) {
      continue;
    }
    Future<ByteData> bytes(String name) async {
      final data = File('${dir.path}/$name').readAsBytesSync();
      return ByteData.view(Uint8List.fromList(data).buffer);
    }

    final roboto = FontLoader('Roboto')
      ..addFont(bytes('Roboto-Regular.ttf'))
      ..addFont(bytes('Roboto-Medium.ttf'))
      ..addFont(bytes('Roboto-Bold.ttf'));
    await roboto.load();
    return;
  }
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
