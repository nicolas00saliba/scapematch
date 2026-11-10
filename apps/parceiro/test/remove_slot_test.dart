import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';
import 'support/sample_clock.dart';

void main() {
  test('a removed demo slot leaves search, the room and booking', () async {
    final database = loadSampleDatabase();
    final clock = loadSampleClock();
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    final catalog = FakeCatalogRepository(database, latency: Duration.zero);
    final partner = PartnerRepository(
      groups: groups,
      catalog: catalog,
      database: database,
      clock: clock,
    );

    final held = database.groups.firstWhere(
      (group) =>
          group.houseId == SampleIds.houseCwbRuaXv &&
          !group.isCancelled &&
          group.startsAt.isAfter(sampleNow) &&
          group.participants.any(_holdsSeat),
    );
    expect(
      await partner.removeSlot(roomId: held.roomId, slotId: held.slotId),
      PartnerMessages.slotHasReservation,
    );
    expect(database.slotById(held.slotId)!.active, isTrue);
    final stillListed = await groups.listByCity(SampleIds.curitiba);
    expect(stillListed.any((group) => group.id == held.id), isTrue);

    final when = DateTime(2027, 3, 2, 14);
    expect(
      await partner.openSession(
        houseId: SampleIds.houseCwbRuaXv,
        roomId: SampleIds.roomCwbCaldeira,
        startsAt: when,
        priceCents: 8000,
      ),
      isNull,
    );
    final opened = database.slots.lastWhere(
      (slot) =>
          slot.roomId == SampleIds.roomCwbCaldeira && slot.startsAt == when,
    );
    final before = await groups.listByCity(SampleIds.curitiba);
    expect(before.any((group) => group.slotId == opened.id), isTrue);

    expect(
      await partner.removeSlot(
        roomId: SampleIds.roomCwbCaldeira,
        slotId: opened.id,
      ),
      isNull,
    );
    expect(database.slotById(opened.id)!.active, isFalse);
    final slots = await catalog.listSlotsByRoom(SampleIds.roomCwbCaldeira);
    expect(slots.any((slot) => slot.id == opened.id), isFalse);
    final after = await groups.listByCity(SampleIds.curitiba);
    expect(after.any((group) => group.slotId == opened.id), isFalse);
    final booked = await groups.create(
      CreateGroupRequest(
        cityId: SampleIds.curitiba,
        houseId: SampleIds.houseCwbRuaXv,
        roomId: SampleIds.roomCwbCaldeira,
        slotId: opened.id,
        extraSpots: 3,
        creatorUserId: 'user-local',
        creatorDisplayName: 'Você',
      ),
    );
    expect(booked, isA<CreateGroupFailure>());
    expect(
      (booked as CreateGroupFailure).reason,
      CreateGroupFailureReason.unknownSelection,
    );

    final snap = await partner.load(SampleIds.houseCwbRuaXv);
    expect(
      snap.slotsByRoom[SampleIds.roomCwbCaldeira]?.any(
        (slot) => slot.id == opened.id,
      ),
      isNot(true),
    );
  });

  testWidgets('the chip asks before removing and reports a reservation', (
    tester,
  ) async {
    await _openRooms(tester, const Size(412, 915));
    final database = loadSampleDatabase();
    final free = _freeFutureSlot(database);
    final held = database.groups.firstWhere(
      (group) =>
          group.houseId == SampleIds.houseCwbRuaXv &&
          !group.isCancelled &&
          group.startsAt.isAfter(sampleNow) &&
          group.participants.any(_holdsSeat),
    );
    final freeIcon = find.byKey(PartnerKeys.partnerRemoveSlotIcon(free.id));
    await tester.scrollUntilVisible(
      freeIcon,
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(freeIcon);
    await tester.pumpAndSettle();

    expect(find.byKey(PartnerKeys.removeSlotDialog), findsOneWidget);
    expect(find.text(PartnerMessages.removeSlotTitle), findsOneWidget);
    expect(find.text(formatSession(free.startsAt)), findsWidgets);
    expect(
      find.text(PartnerMessages.removeSlotBody(formatSession(free.startsAt))),
      findsOneWidget,
    );

    await tester.tap(find.text(PartnerMessages.removeSlotCancel));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.removeSlotDialog), findsNothing);
    expect(find.byKey(PartnerKeys.partnerRemoveSlot(free.id)), findsOneWidget);

    await tester.tap(freeIcon);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.confirmRemoveSlot));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.slotRemoved), findsOneWidget);
    expect(find.byKey(PartnerKeys.partnerRemoveSlot(free.id)), findsNothing);

    final heldIcon = find.byKey(PartnerKeys.partnerRemoveSlotIcon(held.slotId));
    await tester.scrollUntilVisible(
      heldIcon,
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(heldIcon);
    await tester.pumpAndSettle();
    expect(find.text(formatSession(held.startsAt)), findsWidgets);
    await tester.tap(find.byKey(PartnerKeys.confirmRemoveSlot));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.slotHasReservation), findsOneWidget);
    expect(
      find.byKey(PartnerKeys.partnerRemoveSlot(held.slotId)),
      findsOneWidget,
    );
  });

  testWidgets('saves the phone shots of removing a slot', (tester) async {
    if (Platform.environment['SCAPEMATCH_SLOT_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(412, 915);
    await _openRooms(tester, size);
    final database = loadSampleDatabase();
    final free = _freeFutureSlot(database);
    final held = database.groups.firstWhere(
      (group) =>
          group.houseId == SampleIds.houseCwbRuaXv &&
          !group.isCancelled &&
          group.startsAt.isAfter(sampleNow) &&
          group.participants.any(_holdsSeat),
    );

    final freeIcon = find.byKey(PartnerKeys.partnerRemoveSlotIcon(free.id));
    await tester.scrollUntilVisible(
      freeIcon,
      400,
      scrollable: verticalScrollable,
    );
    await tester.ensureVisible(freeIcon);
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'salas-remover-horario.png', size, freeIcon);

    await tester.tap(freeIcon);
    await tester.pumpAndSettle();
    await _shot(
      tester,
      dir,
      'salas-confirmar-remocao.png',
      size,
      find.byKey(PartnerKeys.removeSlotDialog),
    );
    await tester.tap(find.text(PartnerMessages.removeSlotCancel));
    await tester.pumpAndSettle();

    final heldIcon = find.byKey(PartnerKeys.partnerRemoveSlotIcon(held.slotId));
    await tester.scrollUntilVisible(
      heldIcon,
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(heldIcon);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.confirmRemoveSlot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(
      tester,
      dir,
      'salas-horario-com-reserva.png',
      size,
      find.text(PartnerMessages.slotHasReservation),
    );
  });
}

bool _holdsSeat(Participant participant) {
  return participant.occupiesSeat &&
      (participant.payment == PaymentStatus.pending ||
          participant.payment == PaymentStatus.reserved ||
          participant.payment == PaymentStatus.paid);
}

TimeSlot _freeFutureSlot(FakeDatabase database) {
  final taken = <String>{
    for (final group in database.groups)
      if (!group.isCancelled && group.participants.any(_holdsSeat))
        group.slotId,
  };
  return database.slots.firstWhere(
    (slot) =>
        slot.roomId == SampleIds.roomCwbCaldeira &&
        slot.active &&
        slot.startsAt.isAfter(sampleNow) &&
        !taken.contains(slot.id),
  );
}

Future<void> _openRooms(WidgetTester tester, Size size) async {
  await pumpParceiro(
    tester,
    size: size,
    overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
  );
  await tester.enterText(
    find.byKey(PartnerKeys.partnerEmail),
    partnerDemoAccount.email,
  );
  await tester.enterText(
    find.byKey(PartnerKeys.partnerPassword),
    partnerDemoPassword,
  );
  await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
  await tester.pumpAndSettle();
  final rooms = find.text(PartnerMessages.rooms);
  await tester.ensureVisible(rooms);
  await tester.tap(rooms);
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();
  const candidates = [
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
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
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
