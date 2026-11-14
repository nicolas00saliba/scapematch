import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_home_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  for (final size in const [Size(412, 1400), Size(1280, 1400)]) {
    testWidgets('a aba Saques concentra o saque em ${size.width.round()}', (
      tester,
    ) async {
      await _pump(tester, size);

      expect(find.text(PartnerMessages.balanceTitle), findsOneWidget);
      expect(find.byKey(PartnerKeys.openWithdrawals), findsOneWidget);
      expect(find.byKey(PartnerKeys.withdrawalSubmit), findsNothing);
      expect(find.byKey(PartnerKeys.withdrawals), findsNothing);

      await tester.ensureVisible(find.byKey(PartnerKeys.withdrawalsTab));
      await tester.tap(find.byKey(PartnerKeys.withdrawalsTab));
      await tester.pumpAndSettle();

      expect(find.text(PartnerMessages.balanceTitle), findsNothing);
      expect(find.byKey(PartnerKeys.withdrawals), findsOneWidget);
      expect(find.text(PartnerMessages.withdrawalsTitle), findsNWidgets(2));
      expect(
        find.text(PartnerMessages.withdrawalBalanceSection),
        findsOneWidget,
      );
      expect(find.text(PartnerMessages.withdrawalHistory), findsOneWidget);
      expect(find.text(PartnerMessages.withdrawalBank), findsOneWidget);
      expect(find.text(PartnerMessages.withdrawalHowTitle), findsOneWidget);
      expect(find.byKey(PartnerKeys.withdrawalSubmit), findsOneWidget);
      if (size.width >= 960) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          PartnerSection.withdrawals.index,
        );
        expect(find.byIcon(Icons.payments), findsOneWidget);
      } else {
        expect(find.byType(NavigationRail), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(PartnerKeys.withdrawalsTab))
              .selected,
          isTrue,
        );
      }

      await tester.ensureVisible(find.text(PartnerMessages.balance));
      await tester.tap(find.text(PartnerMessages.balance));
      await tester.pumpAndSettle();
      expect(find.byKey(PartnerKeys.withdrawalSubmit), findsNothing);
      expect(find.byKey(PartnerKeys.openWithdrawals), findsOneWidget);
    });
  }

  testWidgets('Ver saques no extrato abre a aba', (tester) async {
    await _pump(tester, const Size(412, 1400));
    await tester.tap(find.byKey(PartnerKeys.openWithdrawals));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.withdrawals), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(PartnerKeys.withdrawalsTab))
          .selected,
      isTrue,
    );
  });
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        venueWithdrawalRepositoryProvider.overrideWithValue(
          MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PartnerHome(snapshot: _snapshot()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PartnerSnapshot _snapshot() {
  return PartnerSnapshot(
    house: const EscapeHouse(
      id: 'casa-1',
      cityId: 'curitiba',
      name: 'Casa do Saque',
      neighborhood: 'Centro',
      latitude: -25.4,
      longitude: -49.2,
      receivesPayments: true,
    ),
    now: DateTime(2026, 11, 12, 12),
    grossCents: 20000,
    commissionCents: 2000,
    netCents: 18000,
    reservedCents: 4000,
    lines: const [],
    moneyByGroup: const {},
    groups: const [],
    rooms: const [],
    slotsByRoom: const {},
    absenceCounts: const {},
    absenceMarks: const {},
    standings: const {},
    invoices: const [],
    fiscal: demoHouseFiscal,
  );
}
