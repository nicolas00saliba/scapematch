import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/features/map/data/sample_live_presence.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/domain/house_pin.dart';
import 'package:scapematch/features/map/domain/live_seat.dart';
import 'package:scapematch/features/map/domain/nearby_group.dart';
import 'package:scapematch/features/map/domain/pin_cluster.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';

void main() {
  final now = DateTime(2026, 10, 30, 15);

  test('pins keep a fictional point inside the city', () {
    final db = buildSampleDatabase(now: now);
    final boxes =
        <String, ({double south, double north, double west, double east})>{
          SampleIds.curitiba: (
            south: -25.7,
            north: -25.2,
            west: -49.6,
            east: -49.0,
          ),
          SampleIds.saoPaulo: (
            south: -23.8,
            north: -23.3,
            west: -46.9,
            east: -46.4,
          ),
          SampleIds.rioDeJaneiro: (
            south: -23.2,
            north: -22.6,
            west: -43.5,
            east: -42.9,
          ),
          SampleIds.beloHorizonte: (
            south: -20.2,
            north: -19.6,
            west: -44.2,
            east: -43.7,
          ),
          SampleIds.portoAlegre: (
            south: -30.3,
            north: -29.8,
            west: -51.5,
            east: -50.9,
          ),
        };
    for (final house in db.houses) {
      final box = boxes[house.cityId]!;
      expect(
        house.latitude,
        inInclusiveRange(box.south, box.north),
        reason: house.id,
      );
      expect(
        house.longitude,
        inInclusiveRange(box.west, box.east),
        reason: house.id,
      );
    }
  });

  test('a forming house shows a count and the others show a price', () {
    final db = buildSampleDatabase(now: now);
    final pins = buildHousePins(
      houses: db.houses
          .where((house) => house.cityId == SampleIds.curitiba)
          .toList(),
      rooms: db.rooms,
      groups: db.groups
          .where((group) => group.cityId == SampleIds.curitiba)
          .toList(),
      now: now,
    );
    final rua = pins.singleWhere((pin) => pin.house.id == 'cwb-rua-xv');
    final batel = pins.singleWhere((pin) => pin.house.id == 'cwb-batel');
    expect(rua.formingCount, 1);
    expect(rua.isForming, isTrue);
    expect(batel.formingCount, 0);
    expect(batel.priceCents, isNotNull);
    expect(
      formingGroupCount(pins.expand((pin) => pin.groups).toList(), now),
      greaterThan(1),
    );
  });

  test('nearby pins cluster and distant pins stay apart', () {
    final db = buildSampleDatabase(now: now);
    final pins = buildHousePins(
      houses: db.houses
          .where((house) => house.cityId == SampleIds.curitiba)
          .toList(),
      rooms: db.rooms,
      groups: const [],
      now: now,
    );
    final original = pins
        .where(
          (pin) => pin.house.id == 'cwb-rua-xv' || pin.house.id == 'cwb-batel',
        )
        .toList();
    final apart = clusterHousePins(original, zoom: 14);
    expect(apart, hasLength(2));
    expect(apart.every((cluster) => !cluster.isCluster), isTrue);

    final together = clusterHousePins(original, zoom: 8);
    expect(together, hasLength(1));
    expect(together.single.pins, hasLength(2));

    expect(pinPulseScale(t: 0.5, enabled: false), 1);
    expect(pinPulseScale(t: 0.5, enabled: true), greaterThan(1));
  });

  test('radius keeps the nearest groups first and drops the far ones', () {
    final db = buildSampleDatabase(now: now);
    final origin = cityCenters[SampleIds.curitiba]!;
    final near = formingWithinRadius(
      groups: db.groups,
      houses: db.houses,
      origin: origin,
      radiusKm: 5,
      now: now,
    );
    final wide = formingWithinRadius(
      groups: db.groups,
      houses: db.houses,
      origin: origin,
      radiusKm: 20,
      now: now,
    );
    expect(near, isNotEmpty);
    expect(wide.length, greaterThan(near.length));
    for (var index = 1; index < near.length; index++) {
      expect(
        near[index].distanceKm,
        greaterThanOrEqualTo(near[index - 1].distanceKm),
      );
    }
    expect(near.every((item) => item.distanceKm <= 5), isTrue);
    expect(wide.any((item) => item.distanceKm > 5), isTrue);
    expect(formatDistanceKm(1.2), '1,2 km');
    expect(formatDistanceKm(0.8), '800 m');

    final far = const GeoPoint(0, 0);
    final nearest = nearestCityWithFormingGroups(
      origin: far,
      centers: cityCenters,
      groups: db.groups,
      now: now,
    );
    expect(nearest, isNotNull);
    expect(cityCenters.containsKey(nearest), isTrue);
  });

  test('the sample seat prefers a forming group and then stops when full', () {
    final db = buildSampleDatabase(now: now);
    final curitiba = db.groups
        .where((group) => group.cityId == SampleIds.curitiba)
        .toList()
        .reversed
        .toList();
    expect(pickSeatTarget(curitiba, now)!.id, 'grp-cwb-cofre-almost');

    final presence = SampleLivePresence(database: db, clock: FixedClock(now));
    final seat = presence.takeSeat(SampleIds.curitiba);
    expect(seat, isNotNull);
    expect(seat!.groupId, 'grp-cwb-cofre-almost');
    final group = db.groups.singleWhere((item) => item.id == seat.groupId);
    expect(group.participants.last.displayName, seat.displayName);
    expect(group.participants.last.isLocalUser, isFalse);
    expect(group.filledSpots, 6);
    expect(group.phaseAt(now), GroupPhase.readyToReserve);

    final again = presence.takeSeat(SampleIds.curitiba);
    expect(again, isNotNull);
    expect(again!.groupId, isNot('grp-cwb-cofre-almost'));
  });

  testWidgets('denied location explains the fallback and can try again', (
    tester,
  ) async {
    await _openNear(
      tester,
      const Size(390, 844),
      location: const FixedUserLocation.denied(GeoPoint(0, 0)),
    );
    expect(find.byKey(AppKeys.nearNotice), findsOneWidget);
    expect(find.textContaining('centro de Curitiba'), findsOneWidget);
    expect(find.byKey(AppKeys.nearRetry), findsOneWidget);
    expect(find.text(LiveMapMessages.attribution), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pin opens the room and group sheet', (tester) async {
    await _openNear(tester, const Size(390, 844));
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.text('Mapa'), findsNothing);
    expect(find.text('Lista'), findsNothing);

    await tester.tap(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.groupPinSheet), findsOneWidget);
    expect(find.text('O Relógio'), findsWidgets);
    expect(find.text(LiveMapMessages.seeGroup), findsOneWidget);
    expect(find.textContaining('km'), findsWidgets);

    await tester.ensureVisible(find.byKey(AppKeys.groupPinOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.groupPinOpen));
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailScreen), findsOneWidget);
  });

  testWidgets('outside the radius offers the nearest city', (tester) async {
    await _openNear(
      tester,
      const Size(390, 844),
      location: const FixedUserLocation.device(GeoPoint(0, 0)),
    );
    expect(find.byKey(AppKeys.nearEmpty), findsOneWidget);
    expect(find.byKey(AppKeys.nearEmptyCity), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.nearEmptyCity));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.nearEmpty), findsNothing);
    expect(find.byKey(AppKeys.mapSheet), findsOneWidget);
  });

  testWidgets('the home list has no map toggle', (tester) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          const FixedUserLocation.denied(GeoPoint(0, 0)),
        ),
      ],
    );
    expect(find.text('Lista'), findsNothing);
    expect(find.text('Mapa'), findsNothing);
    expect(find.byKey(AppKeys.findGroup), findsOneWidget);
    expect(find.byKey(AppKeys.newsFeed), findsOneWidget);
    expect(find.byKey(AppKeys.promoCarousel), findsOneWidget);
    expect(find.byKey(AppKeys.nearTab), findsOneWidget);
  });

  testWidgets('reduce motion keeps the nearby map still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _openNear(tester, const Size(390, 844));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attribution tap does not throw', (tester) async {
    await _openNear(tester, const Size(390, 844));
    await tester.tap(find.byKey(AppKeys.mapAttribution));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves the map with the drawer and a selected pin', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_MAP_SHOTS'] != '1') {
      return;
    }
    await _saveMapShots(tester);
  });
}

/// O teste de widget troca o [HttpClient] por um que responde 400.
/// [super.createHttpClient] devolve o cliente de verdade.
class _RealHttpOverrides extends HttpOverrides {
  /// O super devolve o HttpClient real. Sem isto, o teste responde 400.
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent =
        'scapematch/0.1 (https://github.com/nicolas00saliba/scapematch)';
    return client;
  }
}

class _FetchedTiles extends TileProvider {
  _FetchedTiles(this.images);

  final Map<String, Uint8List> images;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    final bytes = images[key];
    if (bytes == null) {
      return MemoryImage(_emptyPng);
    }
    return MemoryImage(bytes);
  }
}

final Uint8List _emptyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<Map<String, Uint8List>> _downloadCuritibaTiles() async {
  final client = _RealHttpOverrides().createHttpClient(null);
  final images = <String, Uint8List>{};
  final jobs = <(int, int, int)>[];
  void window(int z, int x0, int x1, int y0, int y1) {
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        jobs.add((z, x, y));
      }
    }
  }

  window(12, 1484, 1490, 2344, 2350);
  window(13, 2968, 2980, 4688, 4700);
  window(14, 5944, 5954, 9384, 9394);
  window(15, 11892, 11906, 18768, 18786);

  Future<void> one((int, int, int) job) async {
    final (z, x, y) = job;
    final request = await client.getUrl(
      Uri.parse(
        liveMapTileUrl(dark: false)
            .replaceAll('{z}', '$z')
            .replaceAll('{x}', '$x')
            .replaceAll('{y}', '$y'),
      ),
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'scapematch/0.1 (dev.scapematch.app)',
    );
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    images['$z/$x/$y'] = Uint8List.fromList(builder.takeBytes());
  }

  for (var index = 0; index < jobs.length; index += 12) {
    final end = index + 12 < jobs.length ? index + 12 : jobs.length;
    await Future.wait(jobs.sublist(index, end).map(one));
  }
  client.close(force: true);
  return images;
}

Future<void> _saveMapShots(WidgetTester tester) async {
  final dir = Directory('/opt/cursor/artifacts/live-map')
    ..createSync(recursive: true);
  final images = await tester.runAsync(_downloadCuritibaTiles);
  expect(images, isNotNull);
  expect(images!.length, greaterThan(20));
  await tester.runAsync(_loadFonts);
  await pumpScapeMatch(
    tester,
    overrides: [
      mapTileProvider.overrideWithValue(_FetchedTiles(images)),
      userLocationSourceProvider.overrideWithValue(
        FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
      ),
    ],
  );
  final context = tester.element(find.text('ScapeMatch'));
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/news/biblioteca.jpg'),
      context,
    ),
  );

  for (final entry in const <(Size, String)>[
    (Size(390, 844), 'map-phone.png'),
    (Size(1280, 800), 'map-1280.png'),
  ]) {
    tester.view.physicalSize = entry.$1;
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    if (find.byKey(AppKeys.mapSheet).evaluate().isEmpty) {
      await tester.tap(find.byKey(AppKeys.nearTab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
    final mapName = entry.$1.width == 390 ? 'map-phone.png' : 'map-1280.png';
    await _capture(tester, find.byKey(AppKeys.mapAttribution), dir, mapName);
    if (entry.$1.width == 390) {
      await tester.tap(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(AppKeys.groupPinSheet),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.byKey(AppKeys.groupPinSheet),
        dir,
        'map-sheet.png',
      );
      Navigator.of(tester.element(find.byKey(AppKeys.groupPinSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.homeTab));
      await tester.pumpAndSettle();
      await _capture(tester, find.text('ScapeMatch'), dir, 'home.png');
    }
  }
}

Future<void> _openNear(
  WidgetTester tester,
  Size size, {
  UserLocationSource? location,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpScapeMatch(
    tester,
    overrides: [
      mapTileProvider.overrideWithValue(MemoryTileProvider()),
      userLocationSourceProvider.overrideWithValue(
        location ?? FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
      ),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.nearTab));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
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

Future<void> _capture(
  WidgetTester tester,
  Finder anchor,
  Directory dir,
  String name,
) async {
  RenderRepaintBoundary? found;
  tester.element(anchor).visitAncestorElements((ancestor) {
    final render = ancestor.renderObject;
    if (render is RenderRepaintBoundary) {
      found = render;
    }
    return true;
  });
  final boundary = found;
  if (boundary == null) {
    return;
  }
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) {
    return;
  }
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) {
    return;
  }
  File('${dir.path}/$name').writeAsBytesSync(bytes.buffer.asUint8List());
}
