import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the simulated payment flow in light and dark', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_PAY_SHARE_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/pagar')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const phone = Size(412, 915);
    const web = Size(1280, 900);

    for (final theme in ['light', 'dark']) {
      final label = theme == 'light' ? 'claro' : 'escuro';
      for (final size in [phone, web]) {
        final width = size.width.round();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _flow(tester, dir, size, theme, '$width-$label');
      }
    }
  });
}

Future<void> _flow(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
) async {
  await pumpScapeMatch(
    tester,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(
        ThemeChoiceStore(saved: theme),
      ),
    ],
  );
  await _resize(tester, size);
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AppKeys.groupSearch), 'Cobertura');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    300,
    scrollable: verticalScrollable,
  );
  await tester.tap(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.joinButton));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
  await tester.scrollUntilVisible(
    find.text('Pagamento'),
    250,
    scrollable: verticalScrollable,
  );
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'pendente-$suffix.png',
    size,
    find.text('Pagamento'),
  );

  await tester.tap(find.byKey(AppKeys.payMyShare));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'pix-$suffix.png',
    size,
    find.text('Pagar minha parte'),
  );

  await tester.tap(find.byKey(AppKeys.payMethodCard));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'cartao-$suffix.png',
    size,
    find.textContaining('Cartão de teste'),
  );

  await tester.tap(find.byKey(AppKeys.paySimulate));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'confirmacao-$suffix.png',
    size,
    find.text('Pagamento confirmado'),
  );

  await tester.tap(find.byKey(AppKeys.payDone));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
  await _shot(
    tester,
    dir,
    'pagaram-$suffix.png',
    size,
    find.text('Sua parte está paga'),
  );
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final assets = <AssetImage>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      AssetImage(photo.asset),
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image is AssetImage) image.image as AssetImage,
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
  // O layer raiz compõe o grupo e o véu. O boundary do sheet não traz a tela de trás.
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
