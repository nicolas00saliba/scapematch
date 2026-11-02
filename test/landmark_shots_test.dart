import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/onboarding/presentation/city_landmarks.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the landmark intro at phone width', (tester) async {
    if (Platform.environment['SCAPEMATCH_LANDMARK_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/landmarks')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(412, 915);
    await pumpScapeMatch(tester, showOnboarding: true);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.nearTitle), findsOneWidget);

    const stops = <(String, String)>[
      (SampleIds.curitiba, 'curitiba'),
      (SampleIds.rioDeJaneiro, 'rio'),
      (SampleIds.beloHorizonte, 'belo-horizonte'),
      (SampleIds.portoAlegre, 'porto-alegre'),
      (SampleIds.saoPaulo, 'sao-paulo'),
    ];
    for (final (cityId, name) in stops) {
      if (cityId != SampleIds.curitiba) {
        await tester.tap(find.byKey(AppKeys.citySelector));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
        await tester.pumpAndSettle();
      }
      final landmark = landmarkFor(cityId);
      await tester.runAsync(
        () => precacheImage(
          AssetImage(landmark.asset),
          tester.element(find.text(OnboardingMessages.nearTitle)),
        ),
      );
      await tester.pump();
      await _shot(
        tester,
        dir,
        'intro-412-$name.png',
        size,
        find.text(OnboardingMessages.nearTitle),
      );
    }
  });
}

Future<void> _loadFonts() async {
  const dir = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
  if (!File('$dir/Roboto-Regular.ttf').existsSync()) {
    return;
  }
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name,
  Size expected,
  Finder anchor,
) async {
  RenderRepaintBoundary? boundary;
  tester.element(anchor).visitAncestorElements((ancestor) {
    final render = ancestor.renderObject;
    if (render is RenderRepaintBoundary &&
        render.size.width >= expected.width - 1 &&
        render.size.height >= expected.height - 1) {
      boundary = render;
    }
    return true;
  });
  final found = boundary;
  expect(found, isNotNull, reason: name);
  final image = await tester.runAsync(() => found!.toImage(pixelRatio: 1));
  expect(image!.width, expected.width.round());
  expect(image.height, expected.height.round());
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
