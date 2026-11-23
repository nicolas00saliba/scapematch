import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/pay_share_sheet.dart';
import 'package:scapematch/features/payments/presentation/installment_grid.dart';
import 'package:scapematch/features/payments/presentation/installment_summary.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  testWidgets('o subquadrinho abre a grade e devolve a opção', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          backendPlanProvider.overrideWithValue(planFor(AppMode.demo)),
          paymentMethodsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    showPayShareSheet(
                      context: context,
                      amountCents: 20000,
                      reference: 'grupo-exemplo',
                      coverAsset: 'assets/images/news/biblioteca.jpg',
                      houseName: 'Biblioteca de São Paulo',
                      roomName: 'Sala Mistério',
                      onPay:
                          (
                            kind, {
                            savedCardId,
                            installments = 1,
                            expectedAmountCents,
                          }) async {
                            return const ShareChargeView(
                              outcome: PaySheetOutcome.reserved,
                            );
                          },
                    );
                  },
                  child: const Text('abrir'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payMethodCard));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.payReservation), findsOneWidget);
    expect(find.text('Biblioteca de São Paulo'), findsOneWidget);
    expect(find.text('Sala Mistério'), findsOneWidget);
    expect(find.text(formatPrice(20000)), findsWidgets);
    expect(find.text('Parcelamento'), findsOneWidget);
    expect(find.text('À vista'), findsOneWidget);
    expect(find.byType(InstallmentGrid), findsNothing);

    final box = tester.getSize(find.byKey(AppKeys.payInstallments));
    expect(box.height, greaterThanOrEqualTo(48));
    expect(box.width, greaterThanOrEqualTo(48));

    await tester.tap(find.byKey(AppKeys.payInstallments));
    await tester.pumpAndSettle();

    expect(find.text(InstallmentPickerPage.title), findsOneWidget);
    expect(find.byKey(AppKeys.installmentPicker), findsOneWidget);
    expect(find.text('sem juros'), findsNWidgets(3));
    final free = tester.widget<Text>(find.text('sem juros').first);
    expect(free.style?.color, const Color(0xFFFFFFFF));
    expect(free.style?.fontWeight, FontWeight.w800);

    await tester.tap(find.byKey(const ValueKey('parcela-3')));
    await tester.pumpAndSettle();

    expect(find.byType(InstallmentGrid), findsNothing);
    expect(find.text('3x sem juros'), findsOneWidget);
    expect(find.text('À vista'), findsNothing);
  });
}
