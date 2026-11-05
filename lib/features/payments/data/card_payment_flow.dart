import 'package:dominio/dominio.dart';

/// Cartão ainda não tokenizado. Só a função `tokenize-card` recebe estes campos.
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

/// Body da tokenização. É o único pedido do app com número, CVV e validade.
Map<String, dynamic> tokenizeCardBody(CardDraft card) {
  return {
    'holder_name': card.holderName,
    'number': card.number,
    'expiry_month': card.expiryMonth,
    'expiry_year': card.expiryYear,
    'ccv': card.ccv,
    if (card.holderCpfCnpj.isNotEmpty) 'holder_cpf_cnpj': card.holderCpfCnpj,
    if (card.holderPostalCode.isNotEmpty)
      'holder_postal_code': card.holderPostalCode,
    if (card.holderAddressNumber.isNotEmpty)
      'holder_address_number': card.holderAddressNumber,
    if (card.holderPhone.isNotEmpty) 'holder_phone': card.holderPhone,
  };
}

/// Body da cobrança. Não tem número, CVV nem validade.
Map<String, dynamic> createChargeBody({
  required String groupId,
  required String idempotencyKey,
  required PaymentMethodKind kind,
  String? savedCardId,
}) {
  return {
    'group_id': groupId,
    'idempotency_key': idempotencyKey,
    'billing_type': kind == PaymentMethodKind.card ? 'CREDIT_CARD' : 'PIX',
    if (kind == PaymentMethodKind.card) 'saved_card_id': savedCardId,
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
    final body = await invoke('tokenize-card', tokenizeCardBody(card));
    return SavedCardRef.fromResponse(body);
  }

  Future<Map<String, dynamic>> charge({
    required String groupId,
    required String idempotencyKey,
    required PaymentMethodKind kind,
    String? savedCardId,
  }) {
    final body = createChargeBody(
      groupId: groupId,
      idempotencyKey: idempotencyKey,
      kind: kind,
      savedCardId: savedCardId,
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
  }) async {
    final saved = await tokenize(card);
    return charge(
      groupId: groupId,
      idempotencyKey: idempotencyKey,
      kind: PaymentMethodKind.card,
      savedCardId: saved.savedCardId,
    );
  }
}
