import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';

void main() {
  test('o número do cartão não sai do aparelho', () async {
    final calls = <String>[];
    final flow = CardPaymentFlow((name, body) async {
      calls.add(name);
      return body;
    });

    expect(
      () => flow.payWithNewCard(
        card: const CardDraft(
          holderName: 'Ana',
          number: '4111111111111111',
          expiryMonth: '12',
          expiryYear: '2028',
          ccv: '123',
        ),
        groupId: 'group-1',
        idempotencyKey: 'idem-12345678',
      ),
      throwsStateError,
    );
    expect(calls, isEmpty);

    final charged = await flow.chargeToken(
      groupId: 'group-1',
      idempotencyKey: 'idem-12345678',
      cardToken: 'tok_mp_1',
    );
    expect(calls, ['create-charge']);
    expect(charged['card_token'], 'tok_mp_1');
    expect(charged.containsKey('number'), isFalse);
    expect(charged.containsKey('ccv'), isFalse);
  });

  test('a cobrança recebe o token e não o número', () async {
    final calls = <Map<String, dynamic>>[];
    final flow = CardPaymentFlow(
      (name, body) async {
        expect(name, 'create-charge');
        calls.add(body);
        return body;
      },
      tokenizeCard: (card) async {
        expect(card.number, '4111111111111111');
        return (id: 'tok_aparelho', paymentMethodId: 'visa');
      },
    );

    final charged = await flow.payWithNewCard(
      card: const CardDraft(
        holderName: 'Ana',
        number: '4111111111111111',
        expiryMonth: '12',
        expiryYear: '2028',
        ccv: '123',
      ),
      groupId: 'group-1',
      idempotencyKey: 'idem-12345678',
    );
    expect(calls, hasLength(1));
    expect(charged['card_token'], 'tok_aparelho');
    expect(charged['payment_method_id'], 'visa');
    expect(charged.containsKey('number'), isFalse);
    expect(charged.containsKey('ccv'), isFalse);
    expect(jsonOf(charged).contains('4111111111111111'), isFalse);
  });
}

String jsonOf(Map<String, dynamic> body) => body.toString();
