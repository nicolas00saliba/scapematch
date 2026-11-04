import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';
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
    final serviceNotes = snap.invoices.where(
      (invoice) => invoice.kind == FiscalInvoiceKind.service,
    );
    final commissionNotes = snap.invoices.where(
      (invoice) => invoice.kind == FiscalInvoiceKind.commission,
    );
    expect(serviceNotes, isNotEmpty);
    expect(commissionNotes.length, serviceNotes.length);
    expect(
      serviceNotes.every(
        (invoice) => invoice.status == FiscalInvoiceStatus.simulated,
      ),
      isTrue,
    );
    expect(
      serviceNotes.map((invoice) => invoice.playerId),
      contains('user-local'),
    );

    final cpf = await partner.load(
      SampleIds.houseCwbRuaXv,
      fiscal: const VenueFiscalProfile(documentKind: FiscalDocumentKind.cpf),
    );
    expect(
      cpf.invoices
          .where((invoice) => invoice.kind == FiscalInvoiceKind.service)
          .every(
            (invoice) => invoice.status == FiscalInvoiceStatus.semEmissao,
          ),
      isTrue,
    );
    expect(
      cpf.invoices
          .where((invoice) => invoice.kind == FiscalInvoiceKind.commission)
          .every(
            (invoice) => invoice.status == FiscalInvoiceStatus.simulated,
          ),
      isTrue,
    );

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
    expect(database.roomById(SampleIds.roomCwbCaldeira)!.priceCents, 8000);
    final before = database.slots.length;
    final slot = await partner.addSlot(
      roomId: SampleIds.roomCwbCaldeira,
      startsAt: sampleNow.add(const Duration(hours: 30)),
    );
    expect(database.slots.length, before + 1);
    expect(database.slotById(slot.id), isNotNull);
  });

  test('a player payment lands in the same house book', () async {
    final database = loadSampleDatabase();
    final clock = loadSampleClock();
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    final partner = PartnerRepository(
      groups: groups,
      catalog: FakeCatalogRepository(database, latency: Duration.zero),
      database: database,
      clock: clock,
    );
    const groupId = 'grp-cwb-lab-quase';
    final joined = await groups.join(
      groupId,
      participantUserId: sampleCurrentUser.id,
      participantName: sampleCurrentUser.displayName,
    );
    expect(joined, isA<JoinSuccess>());
    final paid = await groups.payShare(
      groupId,
      userId: sampleCurrentUser.id,
      kind: PaymentMethodKind.pix,
    );
    expect(paid, isA<PayShareSuccess>());

    final snap = await partner.load(SampleIds.houseCwbRuaXv);
    final group = snap.groups.firstWhere((item) => item.id == groupId);
    final nicolas = group.participants.singleWhere(
      (person) => person.displayName == sampleCurrentUser.displayName,
    );
    expect(nicolas.payment, PaymentStatus.paid);
  });

  test('a and b sign in to the same example house', () {
    expect(
      matchPartnerLogin(partnerQuickUser, partnerQuickPassword)?.houseName,
      partnerDemoAccount.houseName,
    );
    expect(
      matchPartnerLogin(' A ', partnerQuickPassword)?.houseId,
      partnerDemoAccount.houseId,
    );
    expect(
      matchPartnerLogin(partnerDemoAccount.email, partnerDemoPassword)?.email,
      partnerDemoAccount.email,
    );
    expect(matchPartnerLogin(partnerQuickUser, partnerDemoPassword), isNull);
    expect(
      matchPartnerLogin(partnerDemoAccount.email, partnerQuickPassword),
      isNull,
    );
  });

  testWidgets('bad credentials stay on the house login', (tester) async {
    await pumpParceiro(tester);
    expect(find.text('ScapeMatch Parceiro'), findsOneWidget);
    expect(find.text(PartnerMessages.emailHint), findsOneWidget);
    expect(find.text(PartnerMessages.quickDemo), findsOneWidget);
    expect(find.text('App do jogador'), findsNothing);

    await tester.enterText(
      find.byKey(PartnerKeys.partnerEmail),
      partnerDemoAccount.email,
    );
    await tester.enterText(find.byKey(PartnerKeys.partnerPassword), 'errada');
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.badLogin), findsOneWidget);
  });

  testWidgets('a and b open the same example house', (tester) async {
    await pumpParceiro(tester);
    await tester.enterText(find.byKey(PartnerKeys.partnerEmail), 'a');
    await tester.enterText(find.byKey(PartnerKeys.partnerPassword), 'b');
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();
    expect(find.text(partnerDemoAccount.houseName), findsOneWidget);
    expect(find.text('App do jogador'), findsNothing);
  });

  testWidgets('the house desk shows balance, reservations and rooms', (
    tester,
  ) async {
    await _signIn(tester);

    expect(find.text(partnerDemoAccount.houseName), findsOneWidget);
    expect(find.text('App do jogador'), findsNothing);
    final net = tester.widget<Text>(find.byKey(PartnerKeys.partnerNet)).data;
    expect(net, isNot(formatPrice(0)));
    expect(find.byKey(PartnerKeys.partnerGross), findsOneWidget);
    expect(find.byKey(PartnerKeys.partnerCommission), findsOneWidget);
    expect(find.text(PartnerMessages.reservedBody), findsOneWidget);
    expect(find.text('Captura'), findsWidgets);

    await tester.tap(find.text(PartnerMessages.reservations));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.upcoming), findsWidgets);
    expect(find.text('Aberto'), findsWidgets);
    expect(find.text('5 de 6 reservaram'), findsWidgets);
    expect(find.textContaining('· Reservado'), findsWidgets);
    expect(find.textContaining('Bruto'), findsWidgets);
    expect(find.textContaining('Comissão'), findsWidgets);
    expect(find.textContaining('Líquido'), findsWidgets);

    await tester.tap(find.text(PartnerMessages.done));
    await tester.pumpAndSettle();
    expect(find.text('Fechado'), findsWidgets);
    expect(find.textContaining('· Pago'), findsWidgets);

    final olga = '${SampleIds.groupCwbClosed}-p0';
    final absence = find.byKey(
      PartnerKeys.partnerAbsence(SampleIds.groupCwbClosed, olga),
    );
    await tester.scrollUntilVisible(
      absence,
      400,
      scrollable: verticalScrollable,
    );
    await tester.ensureVisible(absence);
    await tester.pumpAndSettle();
    await tester.tap(absence);
    await tester.pumpAndSettle();
    expect(find.text('1 falta · aviso'), findsOneWidget);

    await tester.ensureVisible(find.text(PartnerMessages.rooms));
    await tester.tap(find.text(PartnerMessages.rooms));
    await tester.pumpAndSettle();
    final price = find.byKey(
      PartnerKeys.partnerPrice(SampleIds.roomCwbCaldeira),
    );
    final save = find.byKey(
      PartnerKeys.partnerSavePrice(SampleIds.roomCwbCaldeira),
    );
    await tester.scrollUntilVisible(save, 400, scrollable: verticalScrollable);
    await tester.ensureVisible(price);
    await tester.enterText(price, '80,00');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.priceSaved), findsOneWidget);

    await tester.ensureVisible(find.text(PartnerMessages.invoices));
    await tester.tap(find.text(PartnerMessages.invoices));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nota de teste'), findsWidgets);
    expect(find.text('Serviço da casa'), findsWidgets);
    expect(find.text('Comissão da ScapeMatch'), findsWidgets);
    expect(find.textContaining('Nícolas'), findsWidgets);
  });

  testWidgets('house signup requires the terms and records the version', (
    tester,
  ) async {
    await pumpParceiro(tester);
    await tester.tap(find.byKey(PartnerKeys.partnerTermsDemo));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.reviewBanner), findsOneWidget);
    await tester.enterText(find.byKey(PartnerKeys.partnerSignupName), 'Casa Nova');
    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupEmail),
      'casa@exemplo.invalid',
    );
    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupPassword),
      'senha',
    );
    await tester.ensureVisible(find.byKey(PartnerKeys.partnerSignupSubmit));
    await tester.tap(find.byKey(PartnerKeys.partnerSignupSubmit));
    await tester.pumpAndSettle();
    expect(find.text(PartnerLegal.termsRequired), findsOneWidget);

    await tester.ensureVisible(find.byKey(PartnerKeys.partnerSignupTerms));
    await tester.tap(
      find.descendant(
        of: find.byKey(PartnerKeys.partnerSignupTerms),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(PartnerKeys.partnerSignupSubmit));
    await tester.tap(find.byKey(PartnerKeys.partnerSignupSubmit));
    await tester.pumpAndSettle();
    expect(find.text('Aceite registrado'), findsOneWidget);
    expect(find.textContaining(legalDocumentVersion), findsWidgets);
  });
}

Future<void> _signIn(WidgetTester tester) async {
  await pumpParceiro(tester);
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
}
