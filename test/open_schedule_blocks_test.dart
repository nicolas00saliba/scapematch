import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/open_schedule.dart';
import 'package:scapematch/features/catalog/domain/open_slot.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/catalog/presentation/open_day_block.dart';
import 'package:scapematch/features/catalog/presentation/open_slot_block.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/create_group_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pick_open_slot.dart';
import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  final now = DateTime(2026, 11, 24, 15);

  test('só entram horários livres, futuros e fora da janela de 1 h', () {
    final free = TimeSlot(
      id: 'livre',
      roomId: 'sala-a',
      startsAt: now.add(const Duration(days: 2)),
    );
    final reserved = TimeSlot(
      id: 'reservado',
      roomId: 'sala-a',
      startsAt: now.add(const Duration(days: 1)),
    );
    final removed = TimeSlot(
      id: 'removido',
      roomId: 'sala-b',
      startsAt: now.add(const Duration(days: 2)),
      active: false,
    );
    final past = TimeSlot(
      id: 'passado',
      roomId: 'sala-a',
      startsAt: now.subtract(const Duration(hours: 2)),
    );
    final tooClose = TimeSlot(
      id: 'perto',
      roomId: 'sala-a',
      startsAt: now.add(const Duration(hours: 1)),
    );
    final soon = TimeSlot(
      id: 'em-61',
      roomId: 'sala-b',
      startsAt: now.add(const Duration(minutes: 61)),
    );
    final sameInstant = TimeSlot(
      id: 'outro-id',
      roomId: 'sala-a',
      startsAt: now.add(const Duration(days: 3)),
    );

    final open = bookableSlots(
      now: now,
      slots: [free, reserved, removed, past, tooClose, soon, sameInstant],
      occupancy: [
        SlotOccupancy(
          slotId: reserved.id,
          roomId: reserved.roomId,
          startsAt: reserved.startsAt,
          cancelled: false,
        ),
        SlotOccupancy(
          slotId: 'grupo-cancelado',
          roomId: free.roomId,
          startsAt: free.startsAt,
          cancelled: true,
        ),
        SlotOccupancy(
          slotId: 'outro-grupo',
          roomId: sameInstant.roomId,
          startsAt: sameInstant.startsAt,
          cancelled: false,
        ),
      ],
    );

    expect(open.map((item) => item.slot.id), ['em-61', 'livre']);
    expect(openDaysOf(open), [
      calendarDay(soon.startsAt),
      calendarDay(free.startsAt),
    ]);
    expect(open.first.timeLabel, '16:01');
  });

  testWidgets('o bloco de data mostra só os dias recebidos', (tester) async {
    DateTime? picked;
    final first = DateTime(2026, 11, 26);
    final second = DateTime(2026, 11, 28);
    await _pump(
      tester,
      OpenDayBlock(
        days: [first, second],
        selected: null,
        emptyMessage: 'Esta casa não tem dia com horário livre.',
        onSelected: (day) => picked = day,
      ),
    );

    expect(find.byKey(AppKeys.openDay(2026, 11, 26)), findsOneWidget);
    expect(find.byKey(AppKeys.openDay(2026, 11, 28)), findsOneWidget);
    expect(find.byKey(AppKeys.openDay(2026, 11, 24)), findsNothing);
    expect(find.text('Data'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.openDay(2026, 11, 28)));
    await tester.pump();
    expect(picked, second);
  });

  testWidgets('sem dia livre o bloco explica e não desenha chip', (
    tester,
  ) async {
    await _pump(
      tester,
      const OpenDayBlock(
        days: [],
        selected: null,
        emptyMessage: 'Esta casa não tem dia com horário livre.',
        onSelected: null,
      ),
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      find.text('Esta casa não tem dia com horário livre.'),
      findsOneWidget,
    );
  });

  testWidgets('o bloco de horário agrupa por sala e esconde o dia vazio', (
    tester,
  ) async {
    OpenSlot? picked;
    final day = DateTime(2026, 11, 26);
    final alfa = _room('sala-a', 'Sala Alfa');
    final beta = _room('sala-b', 'Sala Beta');
    final fourteen = OpenSlot(
      slot: TimeSlot(
        id: 'a-14',
        roomId: alfa.id,
        startsAt: DateTime(2026, 11, 26, 14),
      ),
      day: day,
      timeLabel: '14:00',
    );
    final nineteen = OpenSlot(
      slot: TimeSlot(
        id: 'b-19',
        roomId: beta.id,
        startsAt: DateTime(2026, 11, 26, 19),
      ),
      day: day,
      timeLabel: '19:00',
    );

    await _pump(
      tester,
      OpenSlotBlock(
        day: null,
        openings: const [],
        selectedSlotId: null,
        onSelected: (slot) => picked = slot,
      ),
    );
    expect(find.text('Escolha a data para ver os horários.'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    await _pump(
      tester,
      OpenSlotBlock(
        day: day,
        openings: [
          RoomOpenings(room: alfa, slots: [fourteen]),
          RoomOpenings(room: beta, slots: [nineteen]),
        ],
        selectedSlotId: null,
        onSelected: (slot) => picked = slot,
      ),
    );
    expect(find.byKey(AppKeys.openRoom(alfa.id)), findsOneWidget);
    expect(find.byKey(AppKeys.openRoom(beta.id)), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('21:00'), findsNothing);

    await tester.tap(find.byKey(AppKeys.openSlot('b-19')));
    await tester.pump();
    expect(picked?.slot.id, 'b-19');
  });

  testWidgets('a casa de exemplo esconde passado e horário reservado', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.tap(find.byKey(AppKeys.selectionField('house')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.houseSpAugusta)));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.openDays), findsOneWidget);
    expect(find.byKey(AppKeys.openSlots), findsOneWidget);
    expect(find.text('Escolha a data para ver os horários.'), findsOneWidget);
    expect(
      find.byKey(AppKeys.openSlot(SampleIds.slotSpMetroPast)),
      findsNothing,
    );

    await pickOpenSlot(tester, SampleIds.slotSpMetroSun);
    expect(
      find.byKey(AppKeys.openSlot(SampleIds.slotSpMetroSun)),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.openRoom(SampleIds.roomSpMetro)), findsOneWidget);
    expect(
      find.byKey(AppKeys.openSlot(SampleIds.slotSpMetroPast)),
      findsNothing,
    );

    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(find.byKey(AppKeys.selectionField('house')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.housePoaRedencao)));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(CreateGroupScreen));
    final state = ProviderScope.containerOf(context)
        .read(createGroupViewModelProvider);
    expect(
      state.openSlots.any(
        (item) => item.slot.id == SampleIds.slotPoaEstufaTaken,
      ),
      isFalse,
    );
    expect(
      state.openSlots.any(
        (item) => item.slot.id == SampleIds.slotPoaEstufaFree,
      ),
      isTrue,
    );
  });

  testWidgets('salva os dois blocos no celular', (tester) async {
    await tester.runAsync(_loadFonts);
    await pumpScapeMatch(
      tester,
      viewport: const Size(412, 915),
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.selectionField('house')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.houseCwbRuaXv)));
    await tester.pumpAndSettle();

    final scroll = find.descendant(
      of: find.byType(CreateGroupScreen),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.openDays),
      300,
      scrollable: scroll,
    );
    await _shot(tester, 'reserva-data-celular');

    final context = tester.element(find.byType(CreateGroupScreen));
    final state = ProviderScope.containerOf(context)
        .read(createGroupViewModelProvider);
    final byDay = <DateTime, Set<String>>{};
    for (final opening in state.openSlots) {
      byDay.putIfAbsent(opening.day, () => {}).add(opening.slot.roomId);
    }
    DateTime? day;
    for (final entry in byDay.entries) {
      if (entry.value.length >= 2) {
        day = entry.key;
        break;
      }
    }
    day ??= state.openDays.first;
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.openDay(day.year, day.month, day.day)),
      300,
      scrollable: scroll,
    );
    await tester.tap(find.byKey(AppKeys.openDay(day.year, day.month, day.day)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.openDay(day.year, day.month, day.day)),
      -500,
      scrollable: scroll,
    );
    await _shot(tester, 'reserva-horarios-celular');
    expect(find.byKey(AppKeys.openSlots), findsOneWidget);
  });
}

EscapeRoom _room(String id, String name) {
  return EscapeRoom(
    id: id,
    houseId: 'casa',
    name: name,
    theme: '',
    category: RoomCategory.mystery,
    capacity: 6,
    durationMinutes: 60,
    difficulty: Difficulty.medium,
    priceCents: 9000,
  );
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  final selector = find.descendant(
    of: find.byType(CreateGroupScreen),
    matching: find.byKey(AppKeys.citySelector),
  );
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}

Future<void> _loadFonts() async {
  final dir = _fontDir();
  if (dir == null) return;
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

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
