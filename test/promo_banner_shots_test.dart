import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the home carousel and each promo banner', (tester) async {
    if (Platform.environment['SCAPEMATCH_PROMO_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/promos')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await _shotHome(tester, dir, const Size(1440, 900), 'home-1440.png');
    await _shotHome(
      tester,
      dir,
      const Size(390, 844),
      'home-390.png',
      revealPromos: true,
    );

    for (var index = 0; index < promoFlyers.length; index++) {
      final flyer = promoFlyers[index];
      if (index > 0) {
        await tester.tap(find.byKey(AppKeys.carouselNext('promos')));
        await tester.pumpAndSettle();
        await _framePromos(tester);
        await _waitForPhotos(tester);
      }
      await _shot(
        tester,
        dir,
        'home-390-${flyer.id}.png',
        const Size(390, 844),
      );
    }
  });
}

Future<void> _shotHome(
  WidgetTester tester,
  Directory dir,
  Size size,
  String name, {
  bool revealPromos = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await pumpScapeMatch(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  if (revealPromos) {
    await _revealPromos(tester);
  }
  await _waitForPhotos(tester);
  await _shot(tester, dir, name, size);
}

Future<void> _revealPromos(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.promoCarousel),
    240,
    scrollable: verticalScrollable,
  );
  await tester.pumpAndSettle();
  await _framePromos(tester);
}

/// Encosta o bloco de promoções no topo da área rolável, inteiro.
Future<void> _framePromos(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(verticalScrollable);
  final viewTop = tester.getTopLeft(verticalScrollable).dy;
  final rect = tester.getRect(find.byKey(AppKeys.promoCarousel));
  final target = scroll.position.pixels + rect.top - viewTop - 8;
  scroll.position.jumpTo(
    target.clamp(
      scroll.position.minScrollExtent,
      scroll.position.maxScrollExtent,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final assets = <AssetImage>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      if (photo.asset.isNotEmpty) AssetImage(photo.asset),
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
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  const dirs = [
    '/home/ubuntu/sdk/flutter/bin/cache/artifacts/material_fonts',
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
