import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:scapematch/features/payments/data/mp_card_token.dart';

const _card = CardDraft(
  holderName: 'Ana',
  number: '4111111111111111',
  expiryMonth: '12',
  expiryYear: '2028',
  ccv: '123',
  holderCpfCnpj: '12345678909',
);

void main() {
  test('o número vai só para o Mercado Pago', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      expect(request.url.host, mpCardTokenHost);
      expect(
        request.url.queryParameters['public_key'],
        'TEST-public-key-123456',
      );
      if (request.url.path == '/v1/card_tokens') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['card_number'], '4111111111111111');
        expect(body['security_code'], '123');
        return http.Response(jsonEncode({'id': 'tok_mp_1'}), 201);
      }
      expect(request.url.path, '/v1/payment_methods/installments');
      expect(request.url.queryParameters['bin'], '411111');
      expect(request.url.query, isNot(contains('4111111111111111')));
      return http.Response(
        jsonEncode([
          {'payment_method_id': 'visa', 'payment_type_id': 'credit_card'},
        ]),
        200,
      );
    });

    final token = await MpCardTokenizer(
      publicKey: 'TEST-public-key-123456',
      client: client,
    ).tokenize(_card);

    expect(token.id, 'tok_mp_1');
    expect(token.paymentMethodId, 'visa');
    expect(hosts, [mpCardTokenHost, mpCardTokenHost]);
  });

  test('sem Public Key o cartão não sai do aparelho', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 500);
    });
    expect(
      () => MpCardTokenizer(publicKey: '', client: client).tokenize(_card),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test('a função pública entrega a Public Key sem o cartão', () async {
    final names = <String>[];
    final client = MockClient((request) async {
      expect(
        request.url.queryParameters['public_key'],
        'APP_USR-public-key-123456',
      );
      return http.Response(
        jsonEncode({'id': 'tok_mp_2', 'payment_method_id': 'master'}),
        201,
      );
    });
    final token = await MpCardTokenizer(
      publicKey: '',
      client: client,
      fetchPublicKey: () async {
        names.add('mp-public-key');
        return 'APP_USR-public-key-123456';
      },
    ).tokenize(_card);
    expect(names, ['mp-public-key']);
    expect(token.id, 'tok_mp_2');
    expect(token.paymentMethodId, 'master');
  });
}
