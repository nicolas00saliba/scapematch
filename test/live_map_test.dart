import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
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
    final badges = {
      for (final item in near)
        '${item.group.filledSpots}/${item.group.totalSpots}',
    };
    expect(badges, containsAll(['5/9', '1/8', '3/4', '8/10']));
    expect(badges.length, greaterThan(3));
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

    expect(find.text('5/9'), findsWidgets);
    expect(find.text('1/8'), findsWidgets);
    expect(find.text('3/4'), findsWidgets);
    expect(find.text('8/10'), findsWidgets);
    _expectBadgeOnPin(tester, 'grp-curitiba-near-0', '5/9');
    _expectBadgeOnPin(tester, 'grp-curitiba-near-1', '1/8');
    _expectBadgeOnPin(tester, 'grp-curitiba-near-2', '3/4');
    _expectBadgeOnPin(tester, 'grp-curitiba-near-3', '8/10');
    _expectBadgeOnPin(tester, 'grp-curitiba-near-4', '2/5');
    final circle = find.descendant(
      of: find.byKey(AppKeys.mapPin('grp-curitiba-near-0')),
      matching: find.byType(AnimatedContainer),
    );
    final before = tester.getSize(circle);
    await tester.tap(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')));
    await tester.pumpAndSettle();
    expect(tester.getSize(circle).width, greaterThan(before.width));
    expect(find.byKey(AppKeys.groupPinSheet), findsOneWidget);
    expect(find.text('O Relógio'), findsWidgets);
    expect(find.text(LiveMapMessages.seeGroup), findsOneWidget);
    expect(find.textContaining('km'), findsWidgets);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.byType(PersonAvatar), findsWidgets);

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

  testWidgets('wide screen keeps the circle, the dot and the pins on the map', (
    tester,
  ) async {
    await _openNear(tester, const Size(1280, 800));
    final map = tester.getRect(find.byType(FlutterMap));
    expect(map.right, closeTo(1280, 1));
    expect(map.left, greaterThan(300));
    expect(map.width, greaterThan(800));
    expect(
      map.contains(tester.getRect(find.byKey(AppKeys.userDot)).center),
      isTrue,
    );
    expect(
      map.contains(
        tester
            .getRect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')))
            .center,
      ),
      isTrue,
    );
    expect(find.byType(MarkerLayer), findsNWidgets(2));
    expect(find.byKey(AppKeys.radiusCircle), findsOneWidget);
    expect(find.byType(CircleLayer), findsNothing);
    expect(find.text('5/9'), findsWidgets);
    expect(find.text('1/8'), findsWidgets);
    expect(find.text('3/4'), findsWidgets);
    expect(find.text('8/10'), findsWidgets);
    expect(tester.takeException(), isNull);
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

/// Guarda os tiles que o mapa pediu e devolve os que já baixamos.
///
/// O pedido em si sai de [HttpClient] real, fora da zona do teste: o cliente
/// do widget responde 400, e o TLS feito de dentro dela quebra o handshake.
class _CachedTiles extends TileProvider {
  _CachedTiles(this.cache, this.wanted);

  final Map<String, Uint8List> cache;
  final Set<String> wanted;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    wanted.add(key);
    final bytes = cache[key];
    if (bytes == null) {
      return MemoryImage(_emptyTile);
    }
    return MemoryImage(bytes);
  }
}

final Uint8List _emptyTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

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

Future<void> _saveMapShots(WidgetTester tester) async {
  final dir = Directory('/opt/cursor/artifacts/live-map')
    ..createSync(recursive: true);
  await tester.runAsync(_loadFonts);
  final client = await tester.runAsync(
    () async => _RealHttpOverrides().createHttpClient(null),
  );
  expect(client, isNotNull);
  addTearDown(() => client!.close(force: true));
  final cache = <String, Uint8List>{};
  final wanted = <String>{};
  final tiles = _CachedTiles(cache, wanted);

  Future<void> show(Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(tiles),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> open(Size size) async {
    for (var pass = 0; pass < 4; pass++) {
      await show(size);
      final missing = [
        for (final key in wanted)
          if (!cache.containsKey(key)) key,
      ];
      if (missing.isNotEmpty) {
        final fetched = await tester.runAsync(
          () => _downloadTiles(client!, missing),
        );
        cache.addAll(fetched ?? const {});
        continue;
      }
      await _precacheMapPhotos(tester);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (await _mapHasImagery(tester)) {
        return;
      }
    }
    fail('os tiles do mapa não carregaram (${cache.length}/${wanted.length})');
  }

  await open(const Size(390, 844));
  await _captureFrame(tester, dir, 'map-phone.png', const Size(390, 844));

  await tester.tap(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _precacheMapPhotos(tester);
  await tester.pump();
  await tester.drag(find.byKey(AppKeys.groupPinSheet), const Offset(0, -420));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _captureFrame(tester, dir, 'map-sheet.png', const Size(390, 844));

  await open(const Size(1280, 800));
  await _captureFrame(tester, dir, 'map-1280.png', const Size(1280, 800));
}

Future<void> _precacheMapPhotos(WidgetTester tester) async {
  final context = tester.element(find.byKey(AppKeys.appFrame));
  final assets = <String>{
    ...PersonPortraits.assets,
    for (final category in RoomCategory.values) ...[
      roomCategoryImage(category),
      ...roomGallery(category),
    ],
  };
  await tester.runAsync(() async {
    for (final asset in assets) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump();
}

Future<Map<String, Uint8List>> _downloadTiles(
  HttpClient client,
  List<String> keys,
) async {
  final images = <String, Uint8List>{};
  var index = 0;
  Future<void> worker() async {
    while (index < keys.length) {
      final key = keys[index];
      index += 1;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final request = await client.getUrl(
            Uri.parse('https://tile.openstreetmap.org/$key.png'),
          );
          request.headers.set(
            HttpHeaders.userAgentHeader,
            'scapematch/0.1 (dev.scapematch.app)',
          );
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          if (response.statusCode != 200) {
            await response.drain<void>();
            continue;
          }
          final chunks = <int>[];
          await for (final chunk in response) {
            chunks.addAll(chunk);
          }
          final bytes = Uint8List.fromList(chunks);
          if (bytes.length > 32) {
            images[key] = bytes;
            break;
          }
        } catch (_) {}
      }
    }
  }

  await Future.wait([
    for (var workerIndex = 0; workerIndex < 4; workerIndex++) worker(),
  ]);
  return images;
}

Future<ui.Image?> _snapshot(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
) async {
  final pending = Completer<ui.Image?>();
  tester.binding.addPostFrameCallback((_) {
    try {
      boundary
          .toImage(pixelRatio: 1)
          .then(
            pending.complete,
            onError: (Object error, StackTrace stack) {
              // ignore: avoid_print
              print('snapshot falhou: $error');
              pending.complete(null);
            },
          );
    } catch (error) {
      // ignore: avoid_print
      print('snapshot falhou: $error');
      pending.complete(null);
    }
  });
  await tester.pump();
  final image = await tester.runAsync(() => pending.future);
  return image;
}

Future<bool> _mapHasImagery(WidgetTester tester) async {
  final render = tester.renderObject(find.byType(FlutterMap));
  if (render is! RenderRepaintBoundary) {
    // ignore: avoid_print
    print('mapa sem boundary: ${render.runtimeType}');
    return false;
  }
  final image = await _snapshot(tester, render);
  final ready = image;
  if (ready == null) {
    // ignore: avoid_print
    print('snapshot do mapa veio vazio');
    return false;
  }
  final width = ready.width;
  final height = ready.height;
  final data = await tester.runAsync(
    () => ready.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  ready.dispose();
  if (data == null || width < 40 || height < 40) {
    return false;
  }
  final bytes = data.buffer.asUint8List();
  final deviation = _bandDeviation(bytes, width, height, height ~/ 2);
  return deviation > 12;
}

double _bandDeviation(Uint8List bytes, int width, int height, int y0) {
  final samples = <int>[];
  final end = math.min(y0 + 24, height);
  for (var y = y0; y < end; y += 2) {
    for (var x = 8; x < width - 8; x += 8) {
      final index = (y * width + x) * 4;
      final red = bytes[index];
      final green = bytes[index + 1];
      final blue = bytes[index + 2];
      samples.add(((red * 3) + (green * 6) + blue) ~/ 10);
    }
  }
  if (samples.length < 8) {
    return 0;
  }
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  var sum = 0.0;
  for (final sample in samples) {
    final delta = sample - mean;
    sum += delta * delta;
  }
  return math.sqrt(sum / samples.length);
}

/// O selo fica no canto da foto, não solto no mapa.
void _expectBadgeOnPin(WidgetTester tester, String groupId, String badge) {
  final pin = tester.getRect(find.byKey(AppKeys.mapPin(groupId)));
  final label = tester.getRect(find.text(badge));
  expect(
    (label.center - pin.bottomRight).distance,
    lessThan(28),
    reason: badge,
  );
  expect(pin.inflate(4).overlaps(label), isTrue, reason: badge);
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

Future<void> _captureFrame(
  WidgetTester tester,
  Directory dir,
  String name,
  Size expected,
) async {
  final boundary = tester.renderObject(
    find.byKey(AppKeys.appFrame),
  ) as RenderRepaintBoundary;
  final image = await _snapshot(tester, boundary);
  expect(image, isNotNull);
  expect(image!.width, expected.width.round());
  expect(image.height, expected.height.round());
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  expect(bytes, isNotNull);
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
