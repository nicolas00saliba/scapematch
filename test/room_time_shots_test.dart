import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/features/ranking/presentation/room_time_view.dart';

void main() {
  testWidgets('salva o top 10 e o perfil', (tester) async {
    if (Platform.environment['SCAPEMATCH_RANKING_SHOTS'] != '1') return;
    await tester.runAsync(_loadFonts);
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await _shot(
      tester,
      dir,
      'ranking-sala-top10',
      const Size(390, 1280),
      RoomTimeBoard(lines: _lines()),
    );
    await _shot(
      tester,
      dir,
      'ranking-perfil',
      const Size(390, 720),
      MyRoomTimesView(lines: _mine()),
    );
  });
}

List<RoomTimeLine> _lines() {
  const names = [
    'Os Ninjas',
    'Equipe Leste',
    'Sem Pressa',
    'Grupo',
    'Os Vizinhos',
    'Chave Mestra',
    'Sala Cheia',
    'Primeira Vez',
    'Depois do Café',
    'Quase Lá',
  ];
  return [
    for (var index = 0; index < names.length; index++)
      RoomTimeLine(
        place: index + 1,
        groupName: names[index],
        elapsedSeconds: (38 + index) * 60 + 12,
        remainingSeconds: 60 * 60 - ((38 + index) * 60 + 12),
        playedOn: DateTime(2026, 11, 2),
        members: index == 0 ? const ['Ana', 'Bruno', 'Caio'] : const ['Lia'],
        escaped: true,
      ),
  ];
}

List<RoomTimeLine> _mine() {
  return [
    RoomTimeLine(
      place: 2,
      roomName: 'O Cofre',
      groupName: 'Equipe Leste',
      elapsedSeconds: 41 * 60 + 5,
      remainingSeconds: 18 * 60 + 55,
      playedOn: DateTime(2026, 11, 2),
      members: const ['Ana', 'Duda'],
      escaped: true,
    ),
    RoomTimeLine(
      roomName: 'O Labirinto',
      groupName: 'Grupo',
      elapsedSeconds: 60 * 60,
      remainingSeconds: 0,
      playedOn: DateTime(2026, 10, 18),
      members: const [],
      escaped: false,
    ),
  ];
}

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name,
  Size size,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [child],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _loadFonts() async {
  const candidates = [
    '/home/ubuntu/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/opt/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? root;
  for (final candidate in candidates) {
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
      root = candidate;
      break;
    }
  }
  if (root == null) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$root/$name').readAsBytesSync();
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
