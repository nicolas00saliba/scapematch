import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('saves the back button on stacked screens', (tester) async {
    if (Platform.environment['SCAPEMATCH_BACK_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/voltar')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const phone = Size(412, 915);
    const web = Size(1280, 900);

    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );

    await _open(tester, '/salas/room-curitiba-near-1', phone);
    await _waitForPhotos(tester);
    expect(find.byKey(AppKeys.scapeBack), findsOneWidget);
    expect(find.text('A Chave'), findsOneWidget);
    await _shot(tester, dir, 'sala-412.png', phone, find.text('A Chave'));

    await _resize(tester, web);
    await _waitForPhotos(tester);
    await _shot(tester, dir, 'sala-1280.png', web, find.text('A Chave'));

    await _open(tester, '/groups/${SampleIds.groupCwbCofreAlmost}', phone);
    await _waitForPhotos(tester);
    await _shot(tester, dir, 'grupo-412.png', phone, find.text('Grupo'));

    await _open(tester, '/groups/new', phone);
    await _shot(tester, dir, 'criar-412.png', phone, find.text('Criar grupo'));

    await _open(tester, '/account/settings', phone);
    await _shot(
      tester,
      dir,
      'configuracoes-412.png',
      phone,
      find.text('Configurações'),
    );

    await _open(tester, '/rooms/${SampleIds.roomCwbCofre}/groups', phone);
    await _shot(
      tester,
      dir,
      'grupos-sala-412.png',
      phone,
      find.text('O Cofre do Café'),
    );

    await _open(tester, '/news/${SampleNewsIds.cwbBiblioteca}', phone);
    await _waitForPhotos(tester);
    await _shot(tester, dir, 'novidade-412.png', phone, find.text('Novidade'));

    await _open(tester, '/convite/${SampleIds.groupCwbCofreAlmost}', phone);
    await _shot(tester, dir, 'convite-412.png', phone, find.text('Convite'));
  });
}

Future<void> _open(WidgetTester tester, String path, Size size) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
  await _resize(tester, size);
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final photos = tester.widgetList<ScapePhoto>(find.byType(ScapePhoto));
  if (photos.isEmpty) {
    return;
  }
  final context = tester.element(find.byType(ScapePhoto).first);
  await tester.runAsync(() async {
    for (final photo in photos) {
      await precacheImage(AssetImage(photo.asset), context);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(
    find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    ),
    findsWidgets,
  );
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
  final visible = anchor.hitTestable();
  final resolved = visible.evaluate().isNotEmpty ? visible.first : anchor.first;
  RenderRepaintBoundary? boundary;
  tester.element(resolved).visitAncestorElements((ancestor) {
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
