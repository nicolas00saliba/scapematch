import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/pay_share_sheet.dart';
import 'package:scapematch/features/payments/domain/card_installments.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';
import 'package:scapematch/providers/repositories.dart';

const _realPix =
    '00020126580014BR.GOV.BCB.PIX0136pagbank.real.payload520400005303986540590.00';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  testWidgets('a demonstração continua com Pix e botão simulados', (
    tester,
  ) async {
    await _open(tester, live: false, onPay: _unusedPay);

    expect(find.text(GroupMessages.simulatedNotice), findsOneWidget);
    expect(find.text(GroupMessages.simulatedPixNotice), findsOneWidget);
    expect(find.text(GroupMessages.simulatePayment), findsOneWidget);
    expect(find.text(GroupMessages.generatePix), findsNothing);
    expect(find.textContaining('scapematch.group-1'), findsOneWidget);
    expect(find.byKey(AppKeys.paySimulate), findsOneWidget);
    expect(find.byKey(AppKeys.payCharge), findsNothing);
  });

  testWidgets('o desconto de primeira reserva aparece na cobrança', (
    tester,
  ) async {
    await _open(tester, live: false, discountCents: 2000, onPay: _unusedPay);
    expect(find.byKey(AppKeys.payFirstDiscount), findsOneWidget);
    expect(find.textContaining('Desconto de primeira reserva'), findsOneWidget);
    expect(find.textContaining('20,00'), findsOneWidget);
    expect(find.byKey(AppKeys.payCharge), findsNothing);
  });

  testWidgets('o modo real mostra o Pix devolvido e não cobra de mentira', (
    tester,
  ) async {
    final calls = <(PaymentMethodKind, String?)>[];
    await _open(
      tester,
      live: true,
      onPay: (kind, {savedCardId, installments = 1, expectedAmountCents}) async {
        calls.add((kind, savedCardId));
        return const ShareChargeView(pixCode: _realPix, pixImageBase64: _png);
      },
    );

    expect(find.text(GroupMessages.simulatedNotice), findsNothing);
    expect(find.text(GroupMessages.simulatedPixNotice), findsNothing);
    expect(find.text(GroupMessages.simulatePayment), findsNothing);
    expect(find.textContaining('scapematch.'), findsNothing);
    expect(find.text(GroupMessages.livePixNotice), findsOneWidget);
    expect(find.text(GroupMessages.chargeOnlyIfCloses), findsNothing);
    expect(find.text(GroupMessages.livePixHint), findsOneWidget);
    expect(find.text(GroupMessages.generatePix), findsOneWidget);
    expect(find.textContaining('Cartão de teste'), findsNothing);

    await tester.tap(find.byKey(AppKeys.payCharge));
    await tester.pumpAndSettle();

    expect(calls, [(PaymentMethodKind.pix, null)]);
    expect(find.text(_realPix), findsOneWidget);
    expect(find.text(GroupMessages.livePixReady), findsOneWidget);
    expect(find.text(GroupMessages.simulatedNotice), findsNothing);
    expect(find.text('Valor reservado'), findsNothing);
    expect(find.byKey(AppKeys.payConfirmed), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(AppKeys.paySimulate), findsNothing);
  });

  testWidgets('erro da cobrança aparece e não vira sucesso', (tester) async {
    await _open(
      tester,
      live: true,
      onPay: (kind, {savedCardId, installments = 1, expectedAmountCents}) async {
        return const ShareChargeView(
          message: 'A casa ainda não tem subconta PagBank.',
        );
      },
    );

    await tester.tap(find.byKey(AppKeys.payCharge));
    await tester.pumpAndSettle();

    expect(find.text('A casa ainda não tem subconta PagBank.'), findsOneWidget);
    expect(find.byKey(AppKeys.payConfirmed), findsNothing);
    expect(find.text(GroupMessages.simulatedNotice), findsNothing);
    expect(find.textContaining('scapematch.'), findsNothing);
  });

  testWidgets('cartão real usa o cartão salvo e não o de teste', (
    tester,
  ) async {
    String? chargedId;
    await _open(
      tester,
      live: true,
      cards: [
        PaymentMethod(
          id: 'card-real',
          brand: CardBrand.visa,
          last4: '1111',
          nickname: 'Pessoal',
        ),
      ],
      onPay: (kind, {savedCardId, installments = 1, expectedAmountCents}) async {
        chargedId = savedCardId;
        expect(kind, PaymentMethodKind.card);
        return const ShareChargeView(outcome: PaySheetOutcome.reserved);
      },
    );

    await tester.tap(find.byKey(AppKeys.payMethodCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('4242'), findsNothing);
    expect(find.textContaining('1111'), findsOneWidget);
    expect(find.text(GroupMessages.payWithCard), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.payCharge));
    await tester.pumpAndSettle();

    expect(chargedId, 'card-real');
    expect(find.text('Valor reservado'), findsOneWidget);
    expect(find.text(GroupMessages.chargeOnlyIfCloses), findsWidgets);
    expect(find.text(GroupMessages.simulatedNotice), findsNothing);
    expect(find.byKey(AppKeys.payConfirmed), findsOneWidget);
  });

  testWidgets('a parcela escolhida vai para a cobrança', (tester) async {
    int? sent;
    int? expected;
    await _open(
      tester,
      live: true,
      amountCents: 20000,
      cards: [
        PaymentMethod(
          id: 'card-real',
          brand: CardBrand.visa,
          last4: '1111',
          nickname: 'Pessoal',
        ),
      ],
      quoteInstallments: (cents) async => cardInstallmentOptions(
        principalCents: cents,
        interestCentsByCount: {4: 640},
      ),
      onPay: (kind, {savedCardId, installments = 1, expectedAmountCents}) async {
        sent = installments;
        expected = expectedAmountCents;
        expect(kind, PaymentMethodKind.card);
        return const ShareChargeView(outcome: PaySheetOutcome.reserved);
      },
    );

    await tester.tap(find.byKey(AppKeys.payMethodCard));
    await tester.pumpAndSettle();
    expect(find.text('sem juros'), findsNWidgets(3));
    expect(find.text('com juros'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('parcela-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payCharge));
    await tester.pumpAndSettle();

    expect(sent, 4);
    expect(expected, 20640);
  });
}

Future<ShareChargeView> _unusedPay(
  PaymentMethodKind kind, {
  String? savedCardId,
  int installments = 1,
  int? expectedAmountCents,
}) async {
  return const ShareChargeView(outcome: PaySheetOutcome.reserved);
}

Future<void> _open(
  WidgetTester tester, {
  required bool live,
  required Future<ShareChargeView> Function(
    PaymentMethodKind kind, {
    String? savedCardId,
    int installments,
    int? expectedAmountCents,
  })
  onPay,
  List<PaymentMethod> cards = const [],
  int discountCents = 0,
  int amountCents = 9000,
  Future<List<CardInstallmentOption>> Function(int principalCents)?
  quoteInstallments,
}) async {
  tester.view.physicalSize = const Size(400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        backendPlanProvider.overrideWithValue(
          planFor(live ? AppMode.real : AppMode.demo),
        ),
        paymentMethodsProvider.overrideWith((ref) async => cards),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showPayShareSheet(
                    context: context,
                    amountCents: amountCents,
                    reference: 'group-1',
                    discountCents: discountCents,
                    quoteInstallments: quoteInstallments,
                    onPay: onPay,
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
}
