import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/data/provider_payments.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/woovi_house_card.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('a flag asaas esconde saldo e saque da Woovi', (tester) async {
    await tester.pumpWidget(_app(stack: 'asaas', repo: _FakePayments()));
    expect(find.byKey(PartnerKeys.wooviBalance), findsNothing);
    expect(find.text(PartnerMessages.groupUnconfirmed), findsNothing);
    expect(find.textContaining('nada é cobrado'), findsNothing);
  });

  testWidgets('a flag woovi mostra saldo, saque e conexão', (tester) async {
    final repo = _FakePayments();
    await tester.pumpWidget(_app(stack: 'woovi', repo: repo));
    await tester.pumpAndSettle();

    expect(find.text(PartnerMessages.groupUnconfirmed), findsOneWidget);
    expect(find.text(PartnerMessages.wooviBalanceTitle), findsOneWidget);
    expect(find.textContaining('80,00'), findsOneWidget);
    expect(find.byKey(PartnerKeys.wooviWithdraw), findsOneWidget);
    expect(find.byKey(PartnerKeys.mpConnect), findsOneWidget);
    expect(find.textContaining('nada é cobrado'), findsNothing);

    await tester.tap(find.byKey(PartnerKeys.wooviWithdraw));
    await tester.pumpAndSettle();
    expect(repo.withdrew, 8000);

    await tester.tap(find.byKey(PartnerKeys.mpConnect));
    await tester.pumpAndSettle();
    expect(repo.opened, 'https://auth.mercadopago.com.br/authorization');
    expect(find.text(PartnerMessages.mpConnected), findsOneWidget);
  });
}

Widget _app({required String stack, required ProviderPaymentsRepository repo}) {
  return ProviderScope(
    overrides: [
      paymentsStackProvider.overrideWithValue(stack),
      providerPaymentsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: WooviHouseCard(
          venueId: 'venue-1',
          launchUrl: (uri) async => true,
        ),
      ),
    ),
  );
}

class _FakePayments implements ProviderPaymentsRepository {
  int? withdrew;
  String? opened;

  @override
  Future<WooviHouseBalance> balance(String venueId) async {
    return const WooviHouseBalance(
      balanceCents: 8000,
      pixKeyMasked: '********@pix',
      canWithdraw: true,
      notice: 'Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.',
    );
  }

  @override
  Future<Uri> mpConnectUrl(String venueId) async {
    opened = 'https://auth.mercadopago.com.br/authorization';
    return Uri.parse(opened!);
  }

  @override
  Future<void> withdraw({
    required String venueId,
    required int amountCents,
  }) async {
    withdrew = amountCents;
  }
}
