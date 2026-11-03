import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the desktop site in light and dark', (tester) async {
    if (Platform.environment['SCAPEMATCH_DESKTOP_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/desktop')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final created = await tester.runAsync(
      () async => _RealHttp().createHttpClient(null),
    );
    final client = created!;
    addTearDown(() => client.close(force: true));
    const phone = Size(412, 915);
    const web = Size(1280, 900);

    for (final theme in ['light', 'dark']) {
      final label = theme == 'light' ? 'claro' : 'escuro';
      for (final size in [phone, web]) {
        final width = size.width.round();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _flow(tester, dir, client, size, theme, '$width-$label');
      }
    }
  });
}

Future<void> _flow(
  WidgetTester tester,
  Directory dir,
  HttpClient client,
  Size size,
  String theme,
  String suffix,
) async {
  final wanted = <String>{};
  final store = _TileBytes();
  final tiles = _ShotTiles(store, wanted, dark: theme == 'dark');
  await pumpScapeMatch(
    tester,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(
        ThemeChoiceStore(saved: theme),
      ),
      mapTileProvider.overrideWithValue(tiles),
      userLocationSourceProvider.overrideWithValue(
        FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
      ),
    ],
  );
  await _resize(tester, size);
  await _waitForPhotos(tester);
  await _shot(tester, dir, 'home-$suffix.png', size, find.text('ScapeMatch'));

  GoRouter.of(
    tester.element(find.byType(Scaffold).first),
  ).go('/sala/${SampleIds.roomCwbCofre}');
  await tester.pumpAndSettle();
  await _waitForPhotos(tester);
  await _shot(
    tester,
    dir,
    'sala-$suffix.png',
    size,
    find.text('O Cofre do Café'),
  );

  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/perto');
  await _until(tester, find.byType(FlutterMap));
  await _fillTiles(tester, client, wanted, store, dark: theme == 'dark');
  await _until(tester, find.byType(FlutterMap));
  await _waitForPhotos(tester);
  await _shot(tester, dir, 'mapa-$suffix.png', size, find.byType(FlutterMap));
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var step = 0; step < 40; step++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent = 'scapematch/0.1 (dev.scapematch.app)';
    return client;
  }
}

class _TileBytes {
  final cache = <String, Uint8List>{};
  final _pending = <String, Completer<Uint8List>>{};

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

class _ShotTiles extends TileProvider {
  _ShotTiles(this.store, this.wanted, {required this.dark});

  final _TileBytes store;
  final Set<String> wanted;
  final bool dark;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key =
        '${dark ? 'dark' : 'light'}/${coordinates.z}/${coordinates.x}/${coordinates.y}';
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
  bool operator ==(Object other) =>
      other is _MemoryTile && other.tileKey == tileKey;

  @override
  int get hashCode => tileKey.hashCode;
}

Future<void> _fillTiles(
  WidgetTester tester,
  HttpClient client,
  Set<String> wanted,
  _TileBytes store, {
  required bool dark,
}) async {
  for (var pass = 0; pass < 6; pass++) {
    await tester.pump();
    final prefix = dark ? 'dark/' : 'light/';
    final missing = [
      for (final key in wanted)
        if (key.startsWith(prefix) && !store.cache.containsKey(key)) key,
    ];
    if (missing.isEmpty) {
      if (wanted.any((key) => key.startsWith(prefix))) {
        await tester.pump(const Duration(milliseconds: 250));
        return;
      }
      continue;
    }
    final fetched = await tester.runAsync(() => _downloadTiles(client, missing));
    store.deliver(fetched ?? const {});
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
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
      final path = key.substring(key.indexOf('/') + 1);
      try {
        final request = await client.getUrl(
          Uri.parse(
            liveMapTileUrl(dark: false).replaceAll('{z}/{x}/{y}', path),
          ),
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
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
