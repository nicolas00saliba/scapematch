import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/room_time_gateway.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_ranking_screen.dart';

void main() {
  testWidgets('salva lançar tempo e o ranking completo', (tester) async {
    if (Platform.environment['SCAPEMATCH_RANKING_SHOTS'] != '1') return;
    await tester.runAsync(_loadFonts);
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await _shot(
      tester,
      dir,
      'ranking-parceiro-lancar',
      const Size(390, 980),
      RoomTimeLaunchForm(
        durationMinutes: 60,
        initialName: 'Os Ninjas',
        members: const [
          RoomTimeMemberDraft(userId: 'ana', label: 'Ana'),
          RoomTimeMemberDraft(userId: 'bruno', label: 'Bruno'),
          RoomTimeMemberDraft(userId: 'caio', label: 'Caio'),
        ],
        onSubmit: (_) async => null,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _shot(
      tester,
      dir,
      'ranking-parceiro-completo',
      const Size(390, 1280),
      RoomTimeHousePanel(
        lines: [
          RoomTimeLine(
            entryId: 't1',
            place: 1,
            groupName: 'Os Ninjas',
            elapsedSeconds: 38 * 60 + 12,
            remainingSeconds: 21 * 60 + 48,
            playedOn: DateTime(2026, 11, 2),
            members: const ['Ana', 'Bruno', 'Caio'],
            escaped: true,
          ),
          RoomTimeLine(
            entryId: 't2',
            place: 2,
            groupName: 'Equipe Leste',
            elapsedSeconds: 41 * 60 + 5,
            remainingSeconds: 18 * 60 + 55,
            playedOn: DateTime(2026, 11, 2),
            members: const ['Marina', 'Duda'],
            escaped: true,
          ),
          RoomTimeLine(
            entryId: 't3',
            place: 3,
            groupName: 'Sem Pressa',
            elapsedSeconds: 49 * 60 + 40,
            remainingSeconds: 10 * 60 + 20,
            playedOn: DateTime(2026, 10, 20),
            members: const ['Caio'],
            escaped: true,
          ),
          RoomTimeLine(
            entryId: 't4',
            place: 4,
            groupName: 'Grupo',
            elapsedSeconds: 52 * 60 + 1,
            remainingSeconds: 7 * 60 + 59,
            playedOn: DateTime(2026, 10, 12),
            members: const [],
            escaped: true,
          ),
          RoomTimeLine(
            entryId: 't5',
            groupName: 'Quase',
            elapsedSeconds: 60 * 60,
            remainingSeconds: 0,
            playedOn: DateTime(2026, 10, 18),
            members: const ['Lia'],
            escaped: false,
          ),
        ],
        showPublic: true,
        showMembers: true,
        onShowPublic: (_) {},
        onShowMembers: (_) {},
        onRemove: (_) async {},
        onEdit: (_, _) async => null,
      ),
    );
  });
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
        appBar: AppBar(title: const Text('Ranking')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [child],
        ),
      ),
    ),
  );
  if (find.byKey(const Key('partner-time-minutes')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('partner-time-minutes')), '38');
    await tester.enterText(find.byKey(const Key('partner-time-seconds')), '12');
  }
  await tester.pump(const Duration(milliseconds: 300));
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
}

Future<void> _loadFonts() async {
  const root =
      '/home/ubuntu/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';
  if (!File('$root/Roboto-Regular.ttf').existsSync()) return;
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
