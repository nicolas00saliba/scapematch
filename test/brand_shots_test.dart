import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the logo on the intro, the home and the icon', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_BRAND_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/marca')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final favicon = File('web/favicon.png').readAsBytesSync();
    final icon = File('web/icons/Icon-512.png').readAsBytesSync();
    const phone = Size(412, 915);
    const web = Size(1280, 900);

    for (final theme in ['light', 'dark']) {
      final label = theme == 'light' ? 'claro' : 'escuro';
      for (final size in [phone, web]) {
        final width = size.width.round();
        final suffix = '$width-$label';
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _app(tester, dir, size, theme, suffix);
        await _icons(tester, dir, size, theme, suffix, favicon, icon);
      }
    }
  });
}

Future<void> _app(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
) async {
  await pumpScapeMatch(
    tester,
    showOnboarding: true,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(
        ThemeChoiceStore(saved: theme),
      ),
    ],
  );
  await _resize(tester, size);
  await _waitForPhotos(tester);
  await _shot(tester, dir, 'intro-$suffix.png', size, find.byType(ScapeLogo));

  await tester.tap(find.byKey(AppKeys.onboardingSkip));
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
  await _shot(tester, dir, 'home-$suffix.png', size, find.byType(ScapeLogo));
}

Future<void> _icons(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
  Uint8List favicon,
  Uint8List icon,
) async {
  final dark = theme == 'dark';
  final faviconImage = MemoryImage(favicon);
  final iconImage = MemoryImage(icon);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image(image: faviconImage, width: 96, height: 96),
              const SizedBox(width: 36),
              Image(image: iconImage, width: 220, height: 220),
            ],
          ),
        ),
      ),
    ),
  );
  final context = tester.element(find.byType(Scaffold));
  await tester.runAsync(() async {
    await precacheImage(faviconImage, context);
    await precacheImage(iconImage, context);
  });
  await tester.pump();
  await _shot(
    tester,
    dir,
    'icone-$suffix.png',
    size,
    find.byType(Image),
  );
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final assets = <AssetImage>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      AssetImage(photo.asset),
  ];
  if (assets.isEmpty) {
    return;
  }
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
  Finder anchor,
) async {
  expect(anchor, findsWidgets, reason: name);
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
