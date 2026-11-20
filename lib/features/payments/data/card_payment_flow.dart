import 'package:dominio/dominio.dart';

/// Dados digitados no aparelho. O número não segue para o servidor.
class CardDraft {
  const CardDraft({
    required this.holderName,
    required this.number,
    required this.expiryMonth,
    required this.expiryYear,
    required this.ccv,
    this.holderCpfCnpj = '',
    this.holderPostalCode = '',
    this.holderAddressNumber = '',
    this.holderPhone = '',
  });

  final String holderName;
  final String number;
  final String expiryMonth;
  final String expiryYear;
  final String ccv;
  final String holderCpfCnpj;
  final String holderPostalCode;
  final String holderAddressNumber;
  final String holderPhone;
}

class SavedCardRef {
  const SavedCardRef({
    required this.savedCardId,
    required this.last4,
    required this.brand,
  });

  final String savedCardId;
  final String last4;
  final String brand;

  factory SavedCardRef.fromResponse(Map<String, dynamic> body) {
    final id = body['saved_card_id'];
    final last4 = body['last4'];
    final brand = body['brand'];
    if (body.containsKey('credit_card_token') ||
        body.containsKey('creditCardToken') ||
        id is! String ||
        id.isEmpty ||
        last4 is! String ||
        brand is! String) {
      throw StateError('tokenize-card devolveu uma resposta inesperada');
    }
    return SavedCardRef(savedCardId: id, last4: last4, brand: brand);
  }
}

typedef FunctionInvoker = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> body,
);

/// O número, o CVV e a validade não entram em pedido nenhum.
Map<String, dynamic> tokenizeCardBody(CardDraft card) {
  if (card.number.isNotEmpty || card.number.isEmpty) {
    throw StateError(
      'O token do cartão nasce no aparelho, no Mercado Pago.',
    );
  }
  return const {};
}

/// Body da cobrança. Não tem número, CVV nem validade.
Map<String, dynamic> createChargeBody({
  required String groupId,
  required String idempotencyKey,
  required PaymentMethodKind kind,
  String? savedCardId,
  String? cardToken,
  int points = 0,
}) {
  return {
    'group_id': groupId,
    'idempotency_key': idempotencyKey,
    'billing_type': kind == PaymentMethodKind.card ? 'CREDIT_CARD' : 'PIX',
    if (kind == PaymentMethodKind.card && savedCardId != null)
      'saved_card_id': savedCardId,
    if (cardToken != null && cardToken.isNotEmpty) 'card_token': cardToken,
    if (points > 0) 'points': points,
  };
}

bool chargeBodyHasRawCard(Map<String, dynamic> body) {
  const raw = {
    'number',
    'ccv',
    'cvv',
    'expiry',
    'expiry_month',
    'expiry_year',
    'expiryMonth',
    'expiryYear',
    'remote_ip',
    'remoteIp',
  };
  return body.keys.any(raw.contains);
}

/// Tokeniza e só então cobra com o id interno devolvido.
class CardPaymentFlow {
  const CardPaymentFlow(this.invoke);

  final FunctionInvoker invoke;

  Future<SavedCardRef> tokenize(CardDraft card) async {
    tokenizeCardBody(card);
    throw StateError(
      'O token do cartão nasce no aparelho, no Mercado Pago.',
    );
  }

  Future<Map<String, dynamic>> charge({
    required String groupId,
    required String idempotencyKey,
    required PaymentMethodKind kind,
    String? savedCardId,
    int points = 0,
  }) {
    final body = createChargeBody(
      groupId: groupId,
      idempotencyKey: idempotencyKey,
      kind: kind,
      savedCardId: savedCardId,
      points: points,
    );
    if (chargeBodyHasRawCard(body)) {
      throw StateError('create-charge não recebe dados do cartão');
    }
    return invoke('create-charge', body);
  }

  Future<Map<String, dynamic>> payWithNewCard({
    required CardDraft card,
    required String groupId,
    required String idempotencyKey,
  }) {
    return tokenize(card).then((_) {
      throw StateError(
        'O token do cartão nasce no aparelho, no Mercado Pago.',
      );
    });
  }

  Future<Map<String, dynamic>> chargeToken({
    required String groupId,
    required String idempotencyKey,
    required String cardToken,
    int points = 0,
  }) {
    final body = createChargeBody(
      groupId: groupId,
      idempotencyKey: idempotencyKey,
      kind: PaymentMethodKind.card,
      cardToken: cardToken,
      points: points,
    );
    if (chargeBodyHasRawCard(body)) {
      throw StateError('create-charge não recebe dados do cartão');
    }
    return invoke('create-charge', body);
  }
}
