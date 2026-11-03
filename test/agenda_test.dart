import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/partner/data/partner_repository.dart';
import 'package:scapematch/features/partner/domain/partner_account.dart';
import 'package:scapematch/features/partner/presentation/partner_messages.dart';

import 'support/pump_app.dart';
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
  });

  testWidgets('the agenda tab shows an open and a closed session', (tester) async {
    await pumpScapeMatch(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/parceiro');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppKeys.partnerEmail), partnerDemoAccount.email);
    await tester.enterText(find.byKey(AppKeys.partnerPassword), partnerDemoPassword);
    await tester.tap(find.byKey(AppKeys.partnerSubmit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PartnerMessages.agenda).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(PartnerMessages.agendaList));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.openGroup), findsWidgets);
    await tester.tap(find.text(PartnerMessages.done));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.closedGroup), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
