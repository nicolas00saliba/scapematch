import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/partner/data/partner_repository.dart';
import 'package:scapematch/features/partner/domain/partner_account.dart';
import 'package:scapematch/features/partner/presentation/partner_messages.dart';
import 'package:scapematch/features/partner/presentation/partner_money.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test('the house statement is the shared ledger', () async {
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
    expect(snap.house.name, partnerDemoAccount.houseName);
    expect(snap.netCents, greaterThan(0));
    expect(snap.grossCents, snap.netCents + snap.commissionCents);
    expect(snap.commissionCents, greaterThan(0));
    expect(snap.reservedCents, greaterThan(0));
    expect(
      snap.lines.map((line) => line.title),
      contains(contains('A Caldeira da XV')),
    );
    expect(
      snap.lines.fold<int>(0, (sum, line) => sum + line.netCents),
      snap.netCents,
    );
    expect(groups.payments.platformBalance, snap.commissionCents);

    final olga = '${SampleIds.groupCwbClosed}-p0';
    final marked = partner.markAbsence(
      houseId: SampleIds.houseCwbRuaXv,
      groupId: SampleIds.groupCwbClosed,
      playerId: olga,
    );
    expect(marked, isA<AbsenceMarked>());
    expect((marked as AbsenceMarked).standing, AbsenceStanding.warned);
    expect(marked.count, 1);
    final again = partner.markAbsence(
      houseId: SampleIds.houseCwbRuaXv,
      groupId: SampleIds.groupCwbClosed,
      playerId: olga,
    );
    expect((again as AbsenceMarked).count, 1);

    final early = partner.markAbsence(
      houseId: SampleIds.houseCwbRuaXv,
      groupId: 'grp-cwb-lab-quase',
      playerId: 'grp-cwb-lab-quase-p0',
    );
    expect(early, isA<AbsenceRejected>());

    expect(parseReais('80,00'), 8000);
    expect(parseReais('80'), 8000);
    final saved = await partner.updatePrice(
      roomId: SampleIds.roomCwbCaldeira,
      priceCents: 8000,
    );
    expect(saved, isNull);
    expect(
      database.roomById(SampleIds.roomCwbCaldeira)!.priceCents,
      8000,
    );
    final before = database.slots.length;
    final slot = await partner.addSlot(
      roomId: SampleIds.roomCwbCaldeira,
      startsAt: sampleNow.add(const Duration(hours: 30)),
    );
    expect(database.slots.length, before + 1);
    expect(database.slotById(slot.id), isNotNull);
  });

  testWidgets('the account shortcut opens the house login', (tester) async {
    await pumpScapeMatch(tester);
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.partnerEntry),
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(find.byKey(AppKeys.partnerEntry));
    await tester.pumpAndSettle();
    expect(find.text('ScapeMatch Parceiro'), findsOneWidget);
    expect(find.text(PartnerMessages.emailHint), findsOneWidget);

    await tester.enterText(
      find.byKey(AppKeys.partnerEmail),
      partnerDemoAccount.email,
    );
    await tester.enterText(find.byKey(AppKeys.partnerPassword), 'errada');
    await tester.tap(find.byKey(AppKeys.partnerSubmit));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.badLogin), findsOneWidget);
  });

  testWidgets('a player reservation shows up for the house', (tester) async {
    await pumpScapeMatch(tester);
    await _openGroup(tester, 'grp-cwb-lab-quase');
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payMyShare));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.paySimulate));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payDone));
    await tester.pumpAndSettle();

    _go(tester, '/parceiro');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(AppKeys.partnerEmail),
      partnerDemoAccount.email,
    );
    await tester.enterText(
      find.byKey(AppKeys.partnerPassword),
      partnerDemoPassword,
    );
    await tester.tap(find.byKey(AppKeys.partnerSubmit));
    await tester.pumpAndSettle();

    expect(find.text(partnerDemoAccount.houseName), findsOneWidget);
    final net = tester.widget<Text>(find.byKey(AppKeys.partnerNet)).data;
    expect(net, isNot(formatPrice(0)));
    expect(find.byKey(AppKeys.partnerGross), findsOneWidget);
    expect(find.byKey(AppKeys.partnerCommission), findsOneWidget);
    expect(find.text(PartnerMessages.reservedBody), findsOneWidget);
    expect(find.text('Captura'), findsWidgets);

    await tester.tap(find.text(PartnerMessages.reservations));
    await tester.pumpAndSettle();
    expect(find.text('Aberto'), findsWidgets);
    expect(find.text('Fechado'), findsWidgets);
    expect(find.text('5 de 6 reservaram'), findsWidgets);
    expect(find.textContaining('· Pago'), findsWidgets);
    expect(find.textContaining('· Reservado'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('Nícolas'),
      400,
      scrollable: verticalScrollable,
    );
    expect(find.textContaining('Nícolas'), findsOneWidget);
    final scroll = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    );
    tester.state<ScrollableState>(scroll.first).position.jumpTo(0);
    await tester.pumpAndSettle();

    final olga = '${SampleIds.groupCwbClosed}-p0';
    final absence = find.byKey(
      AppKeys.partnerAbsence(SampleIds.groupCwbClosed, olga),
    );
    await tester.scrollUntilVisible(absence, 400, scrollable: scroll);
    await tester.ensureVisible(absence);
    await tester.pumpAndSettle();
    await tester.tap(absence);
    await tester.pumpAndSettle();
    expect(find.text('1 falta · aviso'), findsOneWidget);

    await tester.ensureVisible(find.text(PartnerMessages.rooms));
    await tester.tap(find.text(PartnerMessages.rooms));
    await tester.pumpAndSettle();
    final price = find.byKey(AppKeys.partnerPrice(SampleIds.roomCwbCaldeira));
    final save = find.byKey(
      AppKeys.partnerSavePrice(SampleIds.roomCwbCaldeira),
    );
    await tester.scrollUntilVisible(save, 400, scrollable: verticalScrollable);
    await tester.ensureVisible(price);
    await tester.enterText(price, '80,00');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.priceSaved), findsOneWidget);

    _go(tester, '/salas/${SampleIds.roomCwbCaldeira}');
    await tester.pumpAndSettle();
    expect(find.textContaining(formatPrice(8000)), findsWidgets);
  });
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

Future<void> _openGroup(WidgetTester tester, String id) async {
  _go(tester, '/groups/$id');
  await tester.pumpAndSettle();
}
