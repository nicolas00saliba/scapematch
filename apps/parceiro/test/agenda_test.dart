import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';
import 'support/sample_clock.dart';

void main() {
  test('a session opened on the agenda is a group and a slot', () async {
    final database = loadSampleDatabase();
    final groups = FakeGroupRepository(
      database,
      clock: loadSampleClock(),
      latency: Duration.zero,
    );
    final partner = PartnerRepository(
      groups: groups,
      catalog: FakeCatalogRepository(database, latency: Duration.zero),
      database: database,
      clock: loadSampleClock(),
    );
    final snap = await partner.load(SampleIds.houseCwbRuaXv);
    final room = snap.rooms.firstWhere(
      (item) => item.id == SampleIds.roomCwbCaldeira,
    );
    final startsAt = DateTime(sampleNow.year, sampleNow.month, sampleNow.day + 2, 16, 30);
    final error = await partner.openSession(
      houseId: SampleIds.houseCwbRuaXv,
      roomId: room.id,
      startsAt: startsAt,
      priceCents: room.priceCents,
    );
    expect(error, isNull);
    expect(
      database.groups.any(
        (group) => group.roomId == room.id && group.startsAt == startsAt,
      ),
      isTrue,
    );
    expect(
      database.slots.any(
        (slot) => slot.roomId == room.id && slot.startsAt == startsAt,
      ),
      isTrue,
    );
    final saved = partner.saveRoom(
      houseId: SampleIds.houseCwbRuaXv,
      name: 'Sala da agenda',
      difficulty: Difficulty.easy,
      durationMinutes: 60,
      minimumPlayers: 2,
      capacity: 6,
      priceCents: 9900,
      accent: 0xFFD2642A,
    );
    expect(saved, isNull);
    expect(database.rooms.any((item) => item.name == 'Sala da agenda'), isTrue);
    final catalog = FakeCatalogRepository(database, latency: Duration.zero);
    final forPlayer = await catalog.listRoomsByCity(snap.house.cityId);
    final created = forPlayer.singleWhere(
      (item) => item.room.name == 'Sala da agenda',
    );
    final slot = await partner.addSlot(
      roomId: created.room.id,
      startsAt: DateTime(sampleNow.year, sampleNow.month, sampleNow.day + 3, 19),
    );
    final slots = await catalog.listSlotsByRoom(created.room.id);
    expect(slots.any((item) => item.id == slot.id), isTrue);
    final again = await partner.load(SampleIds.houseCwbRuaXv);
    expect(again.rooms.any((item) => item.name == 'Sala da agenda'), isTrue);
    expect(
      again.slotsByRoom[created.room.id]?.any((item) => item.id == slot.id),
      isTrue,
    );
  });

  test('agenda, reservas and salas share the same round session times', () async {
    final database = loadSampleDatabase();
    final groups = FakeGroupRepository(
      database,
      clock: loadSampleClock(),
      latency: Duration.zero,
    );
    final partner = PartnerRepository(
      groups: groups,
      catalog: FakeCatalogRepository(database, latency: Duration.zero),
      database: database,
      clock: loadSampleClock(),
    );
    final snap = await partner.load(SampleIds.houseCwbRuaXv);
    expect(snap.groups, isNotEmpty);
    for (final group in snap.groups) {
      expect(
        isHouseHour(group.startsAt),
        isTrue,
        reason: '${group.roomName} ${group.startsAt}',
      );
      final slots = snap.slotsByRoom[group.roomId] ?? const [];
      expect(
        slots.any((slot) => slot.startsAt == group.startsAt),
        isTrue,
        reason: group.id,
      );
    }
    final byId = {for (final group in snap.groups) group.id: group.startsAt};
    expect(byId.length, snap.groups.length);
    expect(
      snap.groups.where((group) => !group.isCancelled && group.startsAt.isAfter(sampleNow)).length,
      greaterThan(2),
    );
    expect(
      snap.groups.where((group) => group.isCancelled && group.cancelReason.isNotEmpty),
      isNotEmpty,
    );
    final missed = snap.groups.firstWhere((group) => group.id == 'grp-cwb-cofre-missed');
    expect(missed.cancelReason, 'O grupo não fechou a tempo');
    final clockOf = <String, DateTime>{};
    for (final group in snap.groups) {
      final key = '${group.roomId}|${group.startsAt.toIso8601String()}';
      expect(clockOf.containsKey(key), isFalse, reason: key);
      clockOf[key] = group.startsAt;
    }
  });

  testWidgets('reservations keep the three lists and the agenda has day week and month', (
    tester,
  ) async {
    await pumpParceiro(tester);
    await tester.enterText(find.byKey(PartnerKeys.partnerEmail), partnerDemoAccount.email);
    await tester.enterText(find.byKey(PartnerKeys.partnerPassword), partnerDemoPassword);
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();

    await tester.tap(find.text(PartnerMessages.reservations).first);
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.upcoming), findsWidgets);
    expect(find.text(PartnerMessages.openGroup), findsWidgets);
    await tester.tap(find.text(PartnerMessages.done));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.closedGroup), findsWidgets);
    await tester.tap(find.text(PartnerMessages.cancelledTab));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.cancelled), findsWidgets);

    await tester.tap(find.text(PartnerMessages.agenda).first);
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.agendaList), findsNothing);
    expect(find.byKey(PartnerKeys.agendaCalendar), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.agendaMonthToggle));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.agendaMiniCalendar), findsOneWidget);
    expect(find.text('S'), findsWidgets);

    await tester.tap(find.byKey(PartnerKeys.agendaViews));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.agendaViewWeek));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.agendaCalendar), findsOneWidget);

    await tester.tap(find.byKey(PartnerKeys.agendaViews));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.agendaViewMonth));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.agendaMonthGrid), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.agendaViews));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.viewYear), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.agendaViewYear));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.agendaYearGrid), findsOneWidget);
    expect(find.text('Janeiro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the agenda fits a phone and a desktop window', (tester) async {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      await pumpParceiro(tester, size: size);
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
      final agenda = find.text(PartnerMessages.agenda);
      await tester.ensureVisible(agenda.first);
      await tester.tap(agenda.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PartnerKeys.agendaMonthToggle));
      await tester.pumpAndSettle();
      expect(find.byKey(PartnerKeys.agendaMiniCalendar), findsOneWidget);
      if (size.width >= 960) {
        final mini = tester.getSize(find.byKey(PartnerKeys.agendaMiniCalendar));
        expect(mini.width, inInclusiveRange(250, 300));
        await tester.tap(find.byKey(PartnerKeys.agendaViewYear));
        await tester.pumpAndSettle();
        expect(find.byKey(PartnerKeys.agendaYearGrid), findsOneWidget);
        await tester.tap(find.byKey(PartnerKeys.agendaViewDay));
      } else {
        await tester.tap(find.byKey(PartnerKeys.agendaViews));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PartnerKeys.agendaViewWeek));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('the rooms tab creates a room and rejects an empty name', (
    tester,
  ) async {
    await pumpParceiro(tester);
    await tester.enterText(find.byKey(PartnerKeys.partnerEmail), partnerDemoAccount.email);
    await tester.enterText(find.byKey(PartnerKeys.partnerPassword), partnerDemoPassword);
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();
    final rooms = find.text(PartnerMessages.rooms);
    await tester.ensureVisible(rooms.first);
    await tester.pumpAndSettle();
    await tester.tap(rooms.first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(PartnerKeys.agendaAddRoom));
    await tester.tap(find.byKey(PartnerKeys.agendaAddRoom));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PartnerKeys.agendaRoomName), 'A');
    await tester.tap(find.byKey(PartnerKeys.agendaSaveRoom));
    await tester.pumpAndSettle();
    expect(find.text('Dê um nome para a sala.'), findsOneWidget);

    await tester.enterText(find.byKey(PartnerKeys.agendaRoomName), 'Sala Nova');
    await tester.tap(find.byKey(PartnerKeys.agendaSaveRoom));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.roomSaved), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final created = find.text('Sala Nova');
    await tester.scrollUntilVisible(created, 400, scrollable: verticalScrollable);
    expect(created, findsWidgets);
    expect(find.text(PartnerMessages.addSlot), findsWidgets);
  });
}
