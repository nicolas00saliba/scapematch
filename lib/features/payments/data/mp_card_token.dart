import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:scapematch/features/payments/data/card_payment_flow.dart';

/// Public Key do build. Vazia no teste, a menos que o comando passe
/// `--dart-define=MP_PUBLIC_KEY=...`.
const String mpPublicKeyFromEnvironment = String.fromEnvironment(
  'MP_PUBLIC_KEY',
);

const String mpCardTokenHost = 'api.mercadopago.com';

/// Token e bandeira devolvidos pelo Mercado Pago. O número fica no aparelho.
class MpDeviceCard {
  const MpDeviceCard({required this.id, required this.paymentMethodId});

  final String id;
  final String paymentMethodId;
}

/// Lê `MP_PUBLIC_KEY` do ambiente da função pública. Não manda o cartão.
Future<String> mpPublicKeyFromInvoke(FunctionInvoker invoke) async {
  final data = await invoke('mp-public-key', const {});
  final key = data['public_key'];
  if (key is! String || key.trim().isEmpty) {
    throw StateError('A Public Key do Mercado Pago não está configurada.');
  }
  return key.trim();
}

/// Troca o cartão por um token direto na API do Mercado Pago.
class MpCardTokenizer {
  const MpCardTokenizer({
    this.publicKey = mpPublicKeyFromEnvironment,
    this.client,
    this.fetchPublicKey,
  });

  final String publicKey;
  final http.Client? client;
  final Future<String> Function()? fetchPublicKey;

  Future<MpDeviceCard> tokenize(CardDraft card) async {
    final key = await _publicKey();
    final httpClient = client ?? http.Client();
    try {
      final created = await _postToken(httpClient, key, card);
      final method =
          created.method ?? await _paymentMethod(httpClient, key, card);
      return MpDeviceCard(id: created.id, paymentMethodId: method);
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<String> _publicKey() async {
    final defined = publicKey.trim();
    if (defined.isNotEmpty) return defined;
    final load = fetchPublicKey;
    if (load == null) {
      throw StateError('A Public Key do Mercado Pago não está configurada.');
    }
    final loaded = (await load()).trim();
    if (loaded.isEmpty) {
      throw StateError('A Public Key do Mercado Pago não está configurada.');
    }
    return loaded;
  }

  Future<({String id, String? method})> _postToken(
    http.Client httpClient,
    String key,
    CardDraft card,
  ) async {
    final response = await httpClient.post(
      Uri.https(mpCardTokenHost, '/v1/card_tokens', {'public_key': key}),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'card_number': card.number,
        'expiration_month': card.expiryMonth,
        'expiration_year': card.expiryYear,
        'security_code': card.ccv,
        'cardholder': {
          'name': card.holderName,
          if (card.holderCpfCnpj.trim().isNotEmpty)
            'identification': {'type': 'CPF', 'number': card.holderCpfCnpj},
        },
      }),
    );
    final payload = _object(response);
    final id = payload['id'];
    if (id is! String || id.trim().isEmpty) {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    final method = payload['payment_method_id'];
    return (
      id: id.trim(),
      method: method is String && method.trim().isNotEmpty
          ? method.trim()
          : null,
    );
  }

  Future<String> _paymentMethod(
    http.Client httpClient,
    String key,
    CardDraft card,
  ) async {
    final digits = card.number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    final response = await httpClient.get(
      Uri.https(mpCardTokenHost, '/v1/payment_methods/installments', {
        'public_key': key,
        'bin': digits.substring(0, 6),
        'amount': '1',
      }),
    );
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    if (body is! List) {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    for (final item in body) {
      if (item is! Map) continue;
      final method = item['payment_method_id'];
      final type = item['payment_type_id'];
      if (method is String &&
          method.trim().isNotEmpty &&
          (type == null || type == 'credit_card')) {
        return method.trim();
      }
    }
    throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
  }

  Map<String, dynamic> _object(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
    }
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    throw StateError('Não foi possível tokenizar o cartão no Mercado Pago.');
  }
}
