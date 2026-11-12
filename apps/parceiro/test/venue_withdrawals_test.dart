import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_withdrawals_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  test('reais text becomes cents', () {
    expect(parseWithdrawalAmount('1.280,50'), 128050);
    expect(parseWithdrawalAmount('10,00'), 1000);
    expect(parseWithdrawalAmount(''), isNull);
  });

  testWidgets('shows balance, receivables and withdrawal history', (
    tester,
  ) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
    await _pump(tester, repo);

    expect(find.text(PartnerMessages.withdrawalsTitle), findsOneWidget);
    expect(find.byKey(PartnerKeys.withdrawalBalance), findsOneWidget);
    expect(find.text(formatPrice(128050)), findsOneWidget);
    expect(find.textContaining('18 nov 2026'), findsOneWidget);
    expect(find.textContaining('Grupo da quinta'), findsOneWidget);
    expect(find.textContaining(PartnerMessages.withdrawalDone), findsOneWidget);
    expect(
      find.textContaining(PartnerMessages.withdrawalPending),
      findsOneWidget,
    );
    expect(
      find.textContaining(PartnerMessages.withdrawalFailed),
      findsOneWidget,
    );
    expect(find.byKey(PartnerKeys.withdrawalReceipt), findsOneWidget);
    expect(find.textContaining('0199'), findsOneWidget);
  });

  testWidgets('refuses an amount above the available balance', (tester) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(PartnerKeys.withdrawalAmount),
      '9.999,00',
    );
    await tester.tap(find.byKey(PartnerKeys.withdrawalSubmit));
    await tester.pumpAndSettle();

    expect(find.text(payoutErrorMessage('saldo')), findsOneWidget);
    expect(find.byKey(PartnerKeys.withdrawalPassword), findsNothing);
    expect(repo.actions, isEmpty);
  });

  testWidgets('asks for the password again before a withdrawal', (
    tester,
  ) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
    await _pump(tester, repo);

    await tester.enterText(find.byKey(PartnerKeys.withdrawalAmount), '10,00');
    await tester.tap(find.byKey(PartnerKeys.withdrawalSubmit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PartnerKeys.withdrawalPassword), 'abc');
    await tester.tap(find.byKey(PartnerKeys.withdrawalConfirm));
    await tester.pumpAndSettle();

    expect(find.text('Informe a senha de novo.'), findsOneWidget);
    expect(repo.actions, isEmpty);

    await tester.enterText(find.byKey(PartnerKeys.withdrawalPassword), 'senha');
    await tester.tap(find.byKey(PartnerKeys.withdrawalConfirm));
    await tester.pumpAndSettle();

    expect(repo.actions, ['withdraw:1000']);
    expect(find.text(formatPrice(127050)), findsOneWidget);
  });

  testWidgets('staff cannot withdraw', (tester) async {
    final repo = MemoryVenueWithdrawalRepository(_staff());
    await _pump(tester, repo);

    expect(find.text(PartnerMessages.withdrawalStaff), findsOneWidget);
    expect(find.byKey(PartnerKeys.withdrawalSubmit), findsNothing);
    expect(find.byKey(PartnerKeys.withdrawalReceipt), findsNothing);
  });

  testWidgets('blocks a destination with a different holder', (tester) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
    await _pump(tester, repo);

    await tester.tap(find.text(PartnerMessages.withdrawalChangeBank));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PartnerKeys.withdrawalDocument),
      '39053344705',
    );
    await tester.enterText(
      find.byKey(PartnerKeys.withdrawalPix),
      '39053344705',
    );
    await tester.tap(find.byKey(PartnerKeys.withdrawalSaveBank));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PartnerKeys.withdrawalPassword), 'senha');
    await tester.tap(find.byKey(PartnerKeys.withdrawalConfirm));
    await tester.pumpAndSettle();

    expect(find.text(payoutErrorMessage('titularidade')), findsOneWidget);
    expect(repo.actions, isEmpty);
  });

  testWidgets('hides the screen when payouts are off', (tester) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.hidden);
    await _pump(tester, repo);

    expect(find.text(PartnerMessages.withdrawalsTitle), findsNothing);
    expect(find.byKey(PartnerKeys.withdrawalSubmit), findsNothing);
  });

  testWidgets('saves the automatic schedule after reauth', (tester) async {
    final repo = MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample());
    await _pump(tester, repo);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PartnerMessages.withdrawalWeekly));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PartnerMessages.withdrawalSaveSchedule));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PartnerKeys.withdrawalPassword), 'senha');
    await tester.tap(find.byKey(PartnerKeys.withdrawalConfirm));
    await tester.pumpAndSettle();

    expect(repo.actions, ['schedule']);
    expect(repo.load('casa'), completion(isA<VenuePayoutSnapshot>()));
    final saved = await repo.load('casa');
    expect(saved.schedule.enabled, isTrue);
    expect(saved.schedule.frequency, 'weekly');
  });
}

VenuePayoutSnapshot _staff() {
  final sample = VenuePayoutSnapshot.sample();
  return VenuePayoutSnapshot(
    enabled: true,
    canWithdraw: false,
    role: 'staff',
    availableCents: sample.availableCents,
    pendingCents: 0,
    schedule: sample.schedule,
    receivables: sample.receivables,
    withdrawals: sample.withdrawals,
    bank: sample.bank,
  );
}

Future<void> _pump(WidgetTester tester, VenueWithdrawalRepository repo) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [venueWithdrawalRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: Locale('pt', 'BR'),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ListView(
            children: [
              VenueWithdrawalsPanel(venueId: 'casa', email: 'casa@example.com'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
