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
    expect(text.contains('https://api-sandbox.asaas.com/v3'), isTrue);
    expect(RegExp(r'\$aact_[A-Za-z0-9_]{8,}').hasMatch(text), isFalse);
  });
}
