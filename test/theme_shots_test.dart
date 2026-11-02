import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart' as tiles;
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves settings, home and the map in both themes', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_THEME_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/theme')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final created = await tester.runAsync(
      () async => _RealHttp().createHttpClient(null),
    );
    expect(created, isNotNull);
    final client = created!;
    addTearDown(() => client.close(force: true));
    final cache = <String, Uint8List>{};
    final wanted = <String>{};
    final store = _TileBytes(cache);
    final provider = _CachedTiles(store, wanted);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _boot(tester, const Size(390, 844), provider);
    await _openSettings(tester);
    await _capture(
      tester,
      dir,
      'settings-390-light.png',
      const Size(390, 844),
      find.text('Aparência'),
    );
    await _resize(tester, const Size(1280, 800));
    await _capture(
      tester,
      dir,
      'settings-1280-light.png',
      const Size(1280, 800),
      find.text('Aparência'),
    );

    await tester.tap(find.byKey(AppKeys.themeChoice('dark')));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      dir,
      'settings-1280-dark.png',
      const Size(1280, 800),
      find.text('Aparência'),
    );
    await _resize(tester, const Size(390, 844));
    await _capture(
      tester,
      dir,
      'settings-390-dark.png',
      const Size(390, 844),
      find.text('Aparência'),
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      dir,
      'home-390-dark.png',
      const Size(390, 844),
      find.text('ScapeMatch'),
    );
    await _resize(tester, const Size(1280, 800));
    await _capture(
      tester,
      dir,
      'home-1280-dark.png',
      const Size(1280, 800),
      find.text('ScapeMatch'),
    );

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountSettings));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.themeChoice('light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      dir,
      'home-1280-light.png',
      const Size(1280, 800),
      find.text('ScapeMatch'),
    );
    await _resize(tester, const Size(390, 844));
    await _capture(
      tester,
      dir,
      'home-390-light.png',
      const Size(390, 844),
      find.text('ScapeMatch'),
    );

    await _openNear(tester);
    await _fillTiles(tester, client, wanted, store);
    expect(cache.length, greaterThan(4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(
      tester,
      dir,
      'map-390-light.png',
      const Size(390, 844),
      find.byType(FlutterMap),
    );
    await _resize(tester, const Size(1280, 800));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await _fillTiles(tester, client, wanted, store);
    expect(cache.length, greaterThan(8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(
      tester,
      dir,
      'map-1280-light.png',
      const Size(1280, 800),
      find.byType(FlutterMap),
    );

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountSettings));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.themeChoice('dark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(
      tester,
      dir,
      'map-1280-dark.png',
      const Size(1280, 800),
      find.byType(FlutterMap),
    );
    await _resize(tester, const Size(390, 844));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(
      tester,
      dir,
      'map-390-dark.png',
      const Size(390, 844),
      find.byType(FlutterMap),
    );
  });
}

Future<void> _boot(
  WidgetTester tester,
  Size size,
  TileProvider provider,
) async {
  await pumpScapeMatch(
    tester,
    overrides: [
      tiles.mapTileProvider.overrideWithValue(provider),
      userLocationSourceProvider.overrideWithValue(
        FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
      ),
    ],
  );
  await _resize(tester, size);
}

Future<void> _fillTiles(
  WidgetTester tester,
  HttpClient client,
  Set<String> wanted,
  _TileBytes store,
) async {
  for (var pass = 0; pass < 5; pass++) {
    await tester.pump();
    final missing = [
      for (final key in wanted)
        if (!store.cache.containsKey(key)) key,
    ];
    if (missing.isEmpty && wanted.isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
    final fetched = await tester.runAsync(
      () => _downloadTiles(client, missing),
    );
    store.deliver(fetched ?? const {});
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
  final missing = [
    for (final key in wanted)
      if (!store.cache.containsKey(key)) key,
  ];
  expect(missing, isEmpty, reason: 'tiles ainda sem bytes');
}

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent = 'scapematch/0.1 (dev.scapematch.app)';
    return client;
  }
}

/// Bytes que chegam depois do [TileLayer] pedir a imagem.
///
/// O mapa guarda o primeiro [ImageProvider]. Se ele já desenhou o PNG vazio,
/// um download posterior não troca o tile. A carga espera o byte real.
class _TileBytes {
  _TileBytes(this.cache);

  final Map<String, Uint8List> cache;
  final Map<String, Completer<Uint8List>> _pending = {};

  Future<Uint8List> bytesFor(String key) {
    final ready = cache[key];
    if (ready != null) {
      return Future<Uint8List>.value(ready);
    }
    return _pending.putIfAbsent(key, Completer<Uint8List>.new).future;
  }

  void deliver(Map<String, Uint8List> fetched) {
    cache.addAll(fetched);
    for (final entry in fetched.entries) {
      final pending = _pending.remove(entry.key);
      if (pending != null && !pending.isCompleted) {
        pending.complete(entry.value);
      }
    }
  }
}

class _CachedTiles extends TileProvider {
  _CachedTiles(this.store, this.wanted);

  final _TileBytes store;
  final Set<String> wanted;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    wanted.add(key);
    return _MemoryTile(key, store);
  }
}

class _MemoryTile extends ImageProvider<_MemoryTile> {
  const _MemoryTile(this.tileKey, this.store);

  final String tileKey;
  final _TileBytes store;

  @override
  Future<_MemoryTile> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_MemoryTile>(this);
  }

  @override
  ImageStreamCompleter loadImage(_MemoryTile key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1);
  }

  Future<ui.Codec> _load(_MemoryTile key, ImageDecoderCallback decode) async {
    final bytes = await key.store.bytesFor(key.tileKey);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is _MemoryTile && other.tileKey == tileKey;
  }

  @override
  int get hashCode => tileKey.hashCode;
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
        if (chunks.length > 32) {
          images[key] = Uint8List.fromList(chunks);
        }
      } catch (_) {}
    }
  }

  await Future.wait([for (var n = 0; n < 4; n++) worker()]);
  return images;
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountSettings));
  await tester.pumpAndSettle();
}

Future<void> _openNear(WidgetTester tester) async {
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
