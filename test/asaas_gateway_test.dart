import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o gateway versionado é o Asaas e não traz chave', () {
    final files = Directory('supabase')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path;
          return path.endsWith('.ts') ||
              path.endsWith('.sql') ||
              path.endsWith('.md') ||
              path.endsWith('.toml');
        });
    final text = files.map((file) => file.readAsStringSync()).join('\n');
    expect(text.contains('mercadopago'), isFalse);
    expect(text.contains('MP_ACCESS_TOKEN'), isFalse);
    expect(text.contains('Mercado Pago'), isFalse);
    expect(text.contains('class AsaasProvider'), isTrue);
    expect(text.contains('ASAAS_API_KEY'), isTrue);
    expect(text.contains('ASAAS_BASE_URL'), isTrue);
    expect(text.contains('ASAAS_WEBHOOK_TOKEN'), isTrue);
    expect(text.contains('asaas-access-token'), isTrue);
    expect(text.contains('authorizeOnly'), isTrue);
    expect(text.contains('/creditCard/tokenizeCreditCard'), isTrue);
    expect(text.contains('creditCardToken'), isTrue);
    final http = File('supabase/functions/_shared/http.ts').readAsStringSync();
    expect(http.contains('https://nicolas00saliba.github.io'), isTrue);
    expect(http.contains('Access-Control-Allow-Origin": "*"'), isFalse);
    expect(http.contains("Access-Control-Allow-Origin': '*'"), isFalse);
    final charge = File(
      'supabase/functions/create-charge/index.ts',
    ).readAsStringSync();
    expect(charge.contains('cardForCharge'), isTrue);
    expect(charge.contains('savedCardView'), isTrue);
    expect(charge.contains('publicError'), isTrue);
    expect(charge.contains('hasRawCardData'), isTrue);
    expect(charge.contains('A cobrança não recebe dados do cartão.'), isTrue);
    expect(charge.contains('tokenizeCreditCard'), isFalse);
    expect(charge.contains('tokenizeCard'), isFalse);
    expect(charge.contains('console.'), isFalse);
    final tokenize = File(
      'supabase/functions/tokenize-card/index.ts',
    ).readAsStringSync();
    expect(tokenize.contains('tokenizeCard'), isTrue);
    expect(tokenize.contains('tokenizePublicResponse'), isTrue);
    expect(tokenize.contains('corsHeadersFor'), isTrue);
    expect(tokenize.contains('console.'), isFalse);
    final responseAt = charge.indexOf('...(cardView ?? {})');
    final response = charge.substring(responseAt - 280, responseAt + 20);
    expect(response.contains('credit_card_token'), isFalse);
    expect(text.contains('my_saved_cards'), isTrue);
    expect(text.contains('saved_cards'), isTrue);
    expect(text.contains('https://api-sandbox.asaas.com/v3'), isTrue);
    expect(text.contains('/invoices'), isTrue);
    expect(text.contains('/fiscalInfo'), isTrue);
    expect(text.contains('fiscal_invoices'), isTrue);
    expect(text.contains('terms_acceptances'), isTrue);
    expect(text.contains('venue_asaas_keys'), isTrue);
    expect(text.contains('accept_terms'), isTrue);
    final provision = File(
      'supabase/functions/provision-venue-wallet/index.ts',
    ).readAsStringSync();
    expect(provision.contains('api_key: created.apiKey'), isTrue);
    expect(provision.contains('wallet_id: created.walletId'), isTrue);
    expect(provision.contains('apiKey: created.apiKey'), isFalse);
    expect(RegExp(r'\$aact_[A-Za-z0-9_]{8,}').hasMatch(text), isFalse);
  });
}
