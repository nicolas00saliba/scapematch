import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';

void main() {
  test('tokenize-card vem antes e create-charge só leva o id', () async {
    final calls = <String>[];
    final flow = CardPaymentFlow((name, body) async {
      calls.add(name);
      if (name == 'tokenize-card') {
        expect(body['number'], '4111111111111111');
        expect(body['ccv'], '123');
        return {
          'saved_card_id': 'card-1',
          'last4': '1111',
          'brand': 'VISA',
        };
      }
      expect(name, 'create-charge');
      expect(chargeBodyHasRawCard(body), isFalse);
      expect(body['saved_card_id'], 'card-1');
      expect(body['billing_type'], 'CREDIT_CARD');
      expect(body.containsKey('number'), isFalse);
      expect(body.containsKey('ccv'), isFalse);
      expect(body.containsKey('expiry_month'), isFalse);
      expect(body.containsKey('expiry_year'), isFalse);
      return {'charge_id': 'ch-1', 'status': 'authorized'};
    });

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

    expect(calls, ['tokenize-card', 'create-charge']);
    expect(charged['charge_id'], 'ch-1');
  });

  test('resposta com token não segue para a cobrança', () async {
    final flow = CardPaymentFlow((name, body) async {
      return {
        'saved_card_id': 'card-1',
        'last4': '1111',
        'brand': 'VISA',
        'credit_card_token': 'tok_vazado',
      };
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
  });
}
