import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/groups/presentation/home_grid_slots.dart';

import 'support/fixed_groups.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('saves home grids with holes and a phone highlight', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_GRID_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/home-grid')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    final curitiba = curitibaSampleGroups();
    await _shot(
      tester,
      dir,
      'home-1440-0-grupos.png',
      const Size(1440, 1180),
      overrides: fixedGroups(const []),
      check: (tester) {
        expect(find.byKey(AppKeys.homeGridSlot(11)), findsOneWidget);
        final bottom = tester
            .getBottomLeft(find.byKey(AppKeys.homeGridSlot(11)))
            .dy;
        final view = tester.view.physicalSize.height;
        expect(bottom, lessThan(view));
      },
    );
    await _shot(
      tester,
      dir,
      'home-1440-3-grupos.png',
      const Size(1440, 1180),
      overrides: fixedGroups(curitiba.take(3).toList()),
      check: (tester) {
        expect(find.text(homeGridCreateMessage), findsWidgets);
        final bottom = tester
            .getBottomLeft(find.byKey(AppKeys.homeGridSlot(8)))
            .dy;
        expect(bottom, lessThan(tester.view.physicalSize.height));
      },
    );
    await _shot(
      tester,
      dir,
      'home-390-0-grupos.png',
      const Size(390, 844),
      overrides: fixedGroups(const []),
      check: (tester) {
        expect(find.byKey(AppKeys.groupWindow), findsNothing);
        expect(find.text('Promoções'), findsOneWidget);
      },
    );
    await _shot(
      tester,
      dir,
      'home-390-2-grupos.png',
      const Size(390, 1100),
      overrides: fixedGroups([
        liveClosing(curitiba[0], missing: 1),
        liveClosing(curitiba[1], missing: 2),
      ]),
      check: (tester) {
        expect(find.text('Falta 1 para confirmar'), findsWidgets);
        expect(find.text('Confirmado — ainda cabem 2'), findsWidgets);
        expect(find.text('Sessão já começou'), findsNothing);
        expect(find.byKey(AppKeys.homeGridSlot(0)), findsNothing);
        final viewBottom = tester.view.physicalSize.height;
        expect(
          tester.getBottomLeft(find.text('Confirmado — ainda cabem 2').first).dy,
          lessThan(viewBottom),
        );
      },
    );
  });
}

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name,
  Size size, {
  required List<Override> overrides,
  required void Function(WidgetTester tester) check,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await pumpScapeMatch(tester, overrides: overrides);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
  check(tester);
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, size.width.round(), reason: name);
  expect(image.height, size.height.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  if (find.byType(Scaffold).evaluate().isEmpty) {
    return;
  }
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
