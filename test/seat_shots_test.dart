import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('saves the seat rules screens at phone width', (tester) async {
    if (Platform.environment['SCAPEMATCH_SEAT_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/seats')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(412, 915);

    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );
    await _resize(tester, size);
    await _shot(tester, dir, 'home-412.png', size, find.text('ScapeMatch'));

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/salas/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();
    await _shot(
      tester,
      dir,
      'sala-412.png',
      size,
      find.text('O Cofre do Café'),
    );

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/groups/${SampleIds.groupCwbCofreAlmost}');
    await tester.pumpAndSettle();
    await tester.drag(find.text('Vagas'), const Offset(0, -240));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'grupo-aberto-412.png', size, find.text('Vagas'));

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.selectionField('house')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option('cwb-rua-xv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.selectionField('room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.roomCwbCofre)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.targetRange),
      200,
      scrollable: verticalScrollable,
    );
    await _shot(
      tester,
      dir,
      'criar-412.png',
      size,
      find.text('Pessoas para fechar'),
    );

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Duração'), const Offset(0, -280));
    await tester.pumpAndSettle();
    await _shot(
      tester,
      dir,
      'mapa-412.png',
      size,
      find.byKey(AppKeys.groupPinSheet),
    );
  });

  testWidgets('saves a closed group at phone width', (tester) async {
    if (Platform.environment['SCAPEMATCH_SEAT_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/seats')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(412, 915);
    final database = loadSampleDatabase();
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(filledSpots: current.totalSpots);

    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        fakeDatabaseProvider.overrideWithValue(database),
      ],
    );
    await _resize(tester, size);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/groups/${SampleIds.groupCwbCofreAlmost}');
    await tester.pumpAndSettle();
    expect(find.text('Grupo fechado'), findsWidgets);
    await tester.drag(find.text('Vagas'), const Offset(0, -240));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'grupo-fechado-412.png', size, find.text('Vagas'));
  });
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
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
