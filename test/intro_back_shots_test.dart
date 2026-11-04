import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the first intro pages with the back arrow', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_INTRO_BACK_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/intro-voltar')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    const wide = Size(1440, 900);
    const phone = Size(390, 844);
    await _open(tester, wide);
    await _shot(tester, dir, 'intro-1440-tela1.png', wide);
    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.onboardingBack), findsOneWidget);
    await _waitForPhotos(tester);
    await _shot(tester, dir, 'intro-1440-tela2-voltar.png', wide);

    await _open(tester, phone);
    await _shot(tester, dir, 'intro-390-tela1.png', phone);
    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.onboardingBack), findsOneWidget);
    await _waitForPhotos(tester);
    await _shot(tester, dir, 'intro-390-tela2-voltar.png', phone);
  });
}

Future<void> _open(WidgetTester tester, Size size) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpScapeMatch(tester, showOnboarding: true);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final assets = <AssetImage>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      if (photo.asset.isNotEmpty) AssetImage(photo.asset),
  ];
  await tester.runAsync(() async {
    for (final asset in assets) {
      await precacheImage(asset, context);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
  await loader.load();
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
) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  expect(image.height, expected.height.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
