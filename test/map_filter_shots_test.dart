import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

/// Prints do mapa com o filtro RPG. O CI pula este teste.
void main() {
  testWidgets('saves the filtered map at 1440 and 390', (tester) async {
    if (Platform.environment['SCAPEMATCH_MAP_FILTER_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final client = await tester.runAsync(
      () async => _RealHttp().createHttpClient(null),
    );
    expect(client, isNotNull);
    addTearDown(() => client!.close(force: true));
    final cache = <String, Uint8List>{};
    final wanted = <String>{};
    final tiles = _CachedTiles(cache, wanted);

    Future<void> open(Size size) async {
      for (var pass = 0; pass < 4; pass++) {
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
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AppKeys.nearTab));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)),
        );
        await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        final missing = [
          for (final key in wanted)
            if (!cache.containsKey(key)) key,
        ];
        if (wanted.isEmpty || missing.isNotEmpty) {
          if (missing.isNotEmpty) {
            final fetched = await tester.runAsync(
              () => _downloadTiles(client!, missing),
            );
            cache.addAll(fetched ?? const {});
          }
          continue;
        }
        final context = tester.element(find.byType(FlutterMap));
        await tester.runAsync(() async {
          for (final key in wanted) {
            final image = tiles.imageFor(key);
            if (image != null) {
              await precacheImage(image, context);
            }
          }
        });
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final late = [
          for (final key in wanted)
            if (!cache.containsKey(key)) key,
        ];
        if (late.isNotEmpty) {
          final fetched = await tester.runAsync(
            () => _downloadTiles(client!, late),
          );
          cache.addAll(fetched ?? const {});
          continue;
        }
        return;
      }
    }

    await open(const Size(1440, 900));
    await _capture(
      tester,
      dir,
      'mapa-filtrado-1440.png',
      const Size(1440, 900),
    );
    wanted.clear();
    await open(const Size(390, 844));
    await _capture(tester, dir, 'mapa-filtrado-390.png', const Size(390, 844));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _CachedTiles extends TileProvider {
  _CachedTiles(this.cache, this.wanted);

  final Map<String, Uint8List> cache;
  final Set<String> wanted;
  final Map<String, MemoryImage> _images = {};

  MemoryImage? imageFor(String key) => _images[key];

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    wanted.add(key);
    final bytes = cache[key];
    if (bytes == null) {
      return MemoryImage(_emptyTile);
    }
    return _images.putIfAbsent(key, () => MemoryImage(bytes));
  }
}

final Uint8List _emptyTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent =
        'scapematch/0.1 (https://github.com/nicolas00saliba/scapematch)';
    return client;
  }
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
      try {
        final request = await client.getUrl(
          Uri.parse(liveMapTileUrl(dark: false).replaceAll('{z}/{x}/{y}', key)),
        );
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'scapematch/0.1 (app.escapematch.com.br)',
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
        }
      } catch (_) {}
    }
  }

  await Future.wait([for (var n = 0; n < 4; n++) worker()]);
  return images;
}

Future<void> _capture(
  WidgetTester tester,
  Directory dir,
  String name,
  Size expected,
) async {
  expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsOneWidget);
  expect(find.text('RPG'), findsWidgets);
  final boundary = tester.renderObject(
    find.byKey(AppKeys.appFrame),
  ) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
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

Future<void> _loadFonts() async {
  const candidates = [
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/sdk/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? dir;
  for (final path in candidates) {
    if (File('$path/Roboto-Regular.ttf').existsSync()) {
      dir = path;
      break;
    }
  }
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
