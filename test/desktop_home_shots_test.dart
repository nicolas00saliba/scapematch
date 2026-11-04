import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the web home and an unchanged phone home', (tester) async {
    if (Platform.environment['SCAPEMATCH_HOME_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/home-web')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await _shotHome(
      tester,
      dir,
      const Size(1280, 720),
      'home-1280.png',
      cityId: SampleIds.saoPaulo,
      showNews: true,
    );
    await _shotHome(
      tester,
      dir,
      const Size(1440, 900),
      'home-1440.png',
      cityId: SampleIds.saoPaulo,
      showNews: true,
    );
    await _shotHome(
      tester,
      dir,
      const Size(390, 844),
      'home-390.png',
      cityId: SampleIds.saoPaulo,
      showNews: false,
    );
  });
}

Future<void> _shotHome(
  WidgetTester tester,
  Directory dir,
  Size size,
  String name, {
  required String cityId,
  required bool showNews,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await pumpScapeMatch(tester);
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);

  if (showNews) {
    final position = tester.state<ScrollableState>(verticalScrollable).position;
    expect(position.pixels, 0, reason: name);
    final viewportTop = tester.getTopLeft(verticalScrollable).dy;
    final viewportBottom = viewportTop + position.viewportDimension;
    final promos = tester.getRect(find.text('Promoções'));
    final news = tester.getRect(find.text('Novidades'));
    expect(promos.top, greaterThanOrEqualTo(viewportTop), reason: name);
    expect(news.bottom, lessThanOrEqualTo(viewportBottom), reason: name);
    expect(find.byKey(AppKeys.carouselNext('news')), findsOneWidget);
    expect(find.byKey(AppKeys.carouselPrevious('news')), findsNothing);
    final card = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('group-card-');
    });
    expect(card, findsWidgets);
    expect(
      tester.getBottomLeft(card.first).dy,
      lessThanOrEqualTo(viewportBottom + 1),
      reason: name,
    );
    expect(
      tester.getTopLeft(card.first).dy,
      greaterThan(news.bottom - 1),
      reason: name,
    );
  } else {
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(AppKeys.groupWindow), findsNothing);
  }

  await _shot(tester, dir, name, size);
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final providers = <ImageProvider>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      AssetImage(photo.asset),
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      image.image,
  ];
  if (providers.isEmpty) {
    return;
  }
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  await tester.pump();
}

Future<void> _loadFonts() async {
  const dirs = [
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
    '/opt/flutter/bin/cache/artifacts/material_fonts',
  ];
  final dir = dirs.cast<String?>().firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
    orElse: () => null,
  );
  if (dir == null) {
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
