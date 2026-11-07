import 'dart:io';
import 'dart:math' as math;
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
    expect(find.byType(PartnerSealDissolve), findsNothing);
    expect(find.byKey(PartnerSealDissolve.sparksKey), findsNothing);
    final heldWord = tester.getRect(_splashWordmark(tester));
    final heldSeal = tester.getRect(_splashSeal(tester));
    await _saveSplashShot(tester, 'parceiro-splash-hold.png');
    final frames = await _beginSplashFrames();
    await _captureSplashFrame(tester, frames, 0);

    var frame = 1;
    frame = await _pumpUntilAbsorb(
      tester,
      frames,
      frame,
      0.30,
      onReach: () async {
        _expectDissolve(tester, heldSeal, heldWord, 0.30);
        await _expectSweptIsBackground(tester);
        await _saveSplashShot(tester, 'parceiro-splash-dissolve-30.png');
      },
    );
    frame = await _pumpUntilAbsorb(
      tester,
      frames,
      frame,
      0.70,
      onReach: () async {
        _expectDissolve(tester, heldSeal, heldWord, 0.70);
        await _expectSweptIsBackground(tester);
        await _saveSplashShot(tester, 'parceiro-splash-dissolve-70.png');
      },
    );
    frame = await _pumpUntilAbsorb(tester, frames, frame, 1);
    expect(_splashLogo(tester).wordmarkAbsorb, 1);
    expect(_splashSeal(tester), findsNothing);
    expect(find.byType(PartnerSealDissolve), findsNothing);

    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      await _captureSplashFrame(tester, frames, frame++);
    }
    expect(_splashWordmark(tester), findsNothing);
    expect(_splashSeal(tester), findsNothing);
    _expectBlackCurtain(tester);
    await _saveSplashShot(tester, 'parceiro-splash-giro.png');
    await _captureSplashFrame(tester, frames, frame);
    await _encodeSplashClip(tester, frames);

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
    expect(find.byType(PartnerSealDissolve), findsNothing);
    expect(find.byKey(PartnerSealDissolve.sparksKey), findsNothing);
    expect(find.byKey(PartnerSealTrain.fadeKey), findsNothing);
    expect(SplashGate.reducedDuration, const Duration(milliseconds: 180));

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
    expect(_splashSeal(tester), findsOneWidget);
    expect(find.byType(PartnerSealDissolve), findsNothing);
    expect(find.byKey(PartnerSealDissolve.sparksKey), findsNothing);
    final fade = tester.widget<Opacity>(find.byKey(PartnerSealTrain.fadeKey));
    expect(fade.opacity, inExclusiveRange(0, 1));

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

void _expectDissolve(
  WidgetTester tester,
  Rect heldSeal,
  Rect heldWord,
  double around,
) {
  final absorb = _splashLogo(tester).wordmarkAbsorb;
  expect(absorb, inInclusiveRange(around - 0.08, around + 0.08));
  final dissolve = tester.widget<PartnerSealDissolve>(
    find.byType(PartnerSealDissolve),
  );
  expect(dissolve.progress, closeTo(absorb, 0.001));
  expect(find.byKey(PartnerSealDissolve.sparksKey), findsOneWidget);
  expect(find.byKey(PartnerSealTrain.fadeKey), findsNothing);
  final seal = tester.getRect(_splashSeal(tester));
  final word = tester.getRect(_splashWordmark(tester));
  expect(seal.left, closeTo(heldSeal.left, 1.5));
  expect(seal.center.dx, closeTo(heldSeal.center.dx, 1.5));
  expect(word.left, lessThan(heldWord.left - 4));
  _expectBlackCurtain(tester);
}

/// À esquerda da frente, fora da faixa das faíscas, o pixel é #111111.
/// Na faixa, o que não é fundo é faísca clara. A direita do corte ainda
/// tem o pêssego do selo.
Future<void> _expectSweptIsBackground(WidgetTester tester) async {
  final seal = tester.getRect(_splashSeal(tester));
  final progress = tester
      .widget<PartnerSealDissolve>(find.byType(PartnerSealDissolve))
      .progress;
  final image = await _splashImage(tester);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final data = bytes!.buffer.asUint8List();
  const bg = 0x11;
  final width = image.width;
  final height = image.height;
  final edge = seal.left + seal.width * progress;
  final strictRight = edge - PartnerSealDissolve.frontBand;
  final top = (seal.top + 1).ceil().clamp(0, height - 1);
  final bottom = (seal.bottom - 1).floor().clamp(0, height);
  final left = seal.left.ceil().clamp(0, width - 1);
  final lastStrict = strictRight.floor().clamp(0, width);
  var swept = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < lastStrict; x++) {
      final i = (y * width + x) * 4;
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      swept++;
      expect(
        (r, g, b),
        (bg, bg, bg),
        reason:
            'resto em ($x,$y) rgb($r,$g,$b), corte em ${edge.toStringAsFixed(1)}',
      );
    }
  }
  expect(swept, greaterThan(20));

  final bandLeft = lastStrict.clamp(0, width - 1);
  final bandRight = edge.ceil().clamp(0, width);
  for (var y = top; y < bottom; y++) {
    for (var x = bandLeft; x < bandRight; x++) {
      final i = (y * width + x) * 4;
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      if (r == bg && g == bg && b == bg) {
        continue;
      }
      expect(r, greaterThanOrEqualTo(bg), reason: 'sombra em ($x,$y)');
      expect(g, greaterThanOrEqualTo(bg), reason: 'sombra em ($x,$y)');
      expect(b, greaterThanOrEqualTo(bg), reason: 'sombra em ($x,$y)');
      expect(
        math.max(r, math.max(g, b)),
        greaterThanOrEqualTo(170),
        reason: 'faísca escura em ($x,$y) rgb($r,$g,$b)',
      );
    }
  }

  var peach = 0;
  final rightStart = (edge + 6).ceil().clamp(0, width);
  final rightEnd = seal.right.floor().clamp(0, width);
  for (var y = top; y < bottom; y += 2) {
    for (var x = rightStart; x < rightEnd; x += 2) {
      final i = (y * width + x) * 4;
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      if (r > 215 && r < 252 && g > 190 && g < 236 && b > 175 && b < 225) {
        peach++;
      }
    }
  }
  image.dispose();
  expect(peach, greaterThan(8));
}

Future<ui.Image> _splashImage(WidgetTester tester) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer! as OffsetLayer;
  final image = await tester.runAsync(
    () => layer.toImage(Offset.zero & view.size),
  );
  return image!;
}

Future<Directory?> _beginSplashFrames() async {
  final artifacts = Directory('/opt/cursor/artifacts');
  if (!artifacts.existsSync()) {
    return null;
  }
  final frames = Directory('/tmp/parceiro-splash-frames');
  if (frames.existsSync()) {
    frames.deleteSync(recursive: true);
  }
  frames.createSync(recursive: true);
  return frames;
}

Future<void> _captureSplashFrame(
  WidgetTester tester,
  Directory? frames,
  int index,
) async {
  if (frames == null) {
    return;
  }
  final image = await _splashImage(tester);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${frames.path}/f${index.toString().padLeft(3, '0')}.png')
      .writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}

Future<int> _pumpUntilAbsorb(
  WidgetTester tester,
  Directory? frames,
  int frame,
  double target, {
  Future<void> Function()? onReach,
}) async {
  var index = frame;
  for (var step = 0; step < 80; step++) {
    if (_splashLogo(tester).wordmarkAbsorb >= target) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 40));
    await _captureSplashFrame(tester, frames, index++);
  }
  expect(
    _splashLogo(tester).wordmarkAbsorb,
    greaterThanOrEqualTo(target - 0.02),
  );
  if (onReach != null) {
    await onReach();
  }
  return index;
}

Future<bool> _ffmpegExists() async {
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<void> _encodeSplashClip(WidgetTester tester, Directory? frames) async {
  if (frames == null) {
    return;
  }
  final canEncode = await tester.runAsync(_ffmpegExists);
  if (canEncode != true) {
    return;
  }
  final results = await tester.runAsync(() async {
    final gif = await Process.run('ffmpeg', [
      '-y',
      '-framerate',
      '12',
      '-i',
      '${frames.path}/f%03d.png',
      '-vf',
      'fps=12,scale=390:-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=80[p];[s1][p]paletteuse',
      '/opt/cursor/artifacts/parceiro-splash.gif',
    ]);
    final video = await Process.run('ffmpeg', [
      '-y',
      '-framerate',
      '12',
      '-i',
      '${frames.path}/f%03d.png',
      '-vf',
      'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-movflags',
      '+faststart',
      '/opt/cursor/artifacts/parceiro-splash.mp4',
    ]);
    return [gif, video];
  });
  expect(results, isNotNull);
  expect(results![0].exitCode, 0, reason: results[0].stderr.toString());
  expect(results[1].exitCode, 0, reason: results[1].stderr.toString());
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
