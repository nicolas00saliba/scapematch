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
}
