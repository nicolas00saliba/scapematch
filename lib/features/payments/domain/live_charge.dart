import 'dart:convert';
import 'dart:typed_data';

/// Cobrança devolvida por `create-charge`. O Pix usa [qrCode] (copia-e-cola)
/// e [qrImageBase64] (QR do Asaas). O app não inventa payload.
class LiveCharge {
  const LiveCharge({
    required this.status,
    required this.billingType,
    required this.qrCode,
    this.qrImageBase64,
    this.pointsOnly = false,
  });

  final String status;
  final String billingType;
  final String qrCode;
  final String? qrImageBase64;

  /// Vaga paga só com pontos. Não existe cobrança nem QR no Asaas.
  final bool pointsOnly;

  bool get isPix => billingType == 'PIX';

  bool get hasPixCode => qrCode.trim().isNotEmpty;

  /// Cartão autorizado reserva a cadeira. Pago fecha a parte.
  /// Pix pendente ainda não reserva: o QR é que segue na tela.
  bool get confirmsSeat => status == 'authorized' || status == 'paid';

  bool get settlesPaid => status == 'paid';

  /// Nulo quando a tela pode mostrar o Pix ou confirmar o cartão.
  String? get rejectionMessage {
    if (billingType != 'PIX' && billingType != 'CREDIT_CARD') {
      return liveChargeFailed;
    }
    if (pointsOnly && settlesPaid) return null;
    if (isPix && !hasPixCode) return livePixMissing;
    if (status == 'failed' || status == 'cancelled' || status == 'refunded') {
      return liveChargeRejected;
    }
    if (!isPix && !confirmsSeat) return liveCardPending;
    return null;
  }

  static LiveCharge fromBody(Map<String, dynamic> body) {
    return LiveCharge(
      status: _text(body['status']).toLowerCase(),
      billingType: _text(body['billing_type']).toUpperCase(),
      qrCode: _text(body['qr_code']),
      qrImageBase64: _optional(body['qr_code_base64']),
      pointsOnly: body['points_only'] == true,
    );
  }
}

const liveChargeFailed = 'Não foi possível criar a cobrança.';
const liveChargeRejected = 'A cobrança não foi aceita.';
const livePixMissing = 'O Asaas não devolveu o código Pix.';
const liveCardPending = 'A cobrança do cartão ainda está pendente.';
const liveCardDeclined = 'O cartão foi recusado.';
const liveChooseCard = 'Escolha um cartão salvo ou preencha um novo.';

/// Texto do campo `error` de `create-charge`, já seguro para mostrar.
/// Código desconhecido ou com cara de segredo vira [liveChargeFailed].
String liveChargeErrorMessage(Object? details) {
  final code = _errorCode(details);
  if (code == null || code.isEmpty) return liveChargeFailed;
  return switch (code) {
    'A casa ainda não tem subconta Asaas.' => code,
    'A casa ainda não pode receber.' => code,
    'A cobrança não recebe dados do cartão.' => code,
    'card_declined' => liveCardDeclined,
    'cpf_required' => 'Para pagar, o Asaas precisa do seu CPF.',
    'asaas_unavailable' => 'O Asaas não respondeu. Tente de novo em instantes.',
    'pix_em_aberto' => 'Já existe um Pix em aberto para esta parte.',
    'pagamento em andamento' =>
      'Há um pagamento em andamento. Espere um instante e tente de novo.',
    'pix_reuse_mismatch' => 'Não foi possível reutilizar o Pix desta parte.',
    'saved_card_id é obrigatório' => liveChooseCard,
    'cartão não encontrado' => 'Não encontramos esse cartão.',
    'group not found' => 'Não encontramos esse grupo.',
    'session started' => 'Esta sessão já começou.',
    'not member' => 'Você não está neste grupo.',
    'not authenticated' => 'Entre de novo para pagar.',
    'group_id e idempotency_key são obrigatórios' => liveChargeFailed,
    'internal_error' || 'erro' || 'ledger_write_failed' => liveChargeFailed,
    _ => _safePublicMessage(code) ?? liveChargeFailed,
  };
}

/// PNG ou JPEG do campo `qr_code_base64`. Outra coisa não vira imagem.
Uint8List? decodePixQrImage(String? encoded) {
  if (encoded == null) return null;
  var text = encoded.trim();
  if (text.isEmpty) return null;
  final comma = text.indexOf(',');
  if (text.startsWith('data:') && comma >= 0) {
    text = text.substring(comma + 1);
  }
  text = text.replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty) return null;
  try {
    final bytes = base64Decode(text);
    if (!_isRasterImage(bytes)) return null;
    return bytes;
  } on FormatException {
    return null;
  }
}

String? _errorCode(Object? details) {
  if (details is Map) {
    final error = details['error'];
    if (error is String) return error.trim();
    return null;
  }
  if (details is! String) return null;
  final text = details.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] is String) {
        return (decoded['error'] as String).trim();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
  return text;
}

String? _safePublicMessage(String code) {
  if (code.length > 180 || code.length < 8) return null;
  if (!code.contains(' ')) return null;
  final lower = code.toLowerCase();
  const blocked = [
    'aact_',
    'bearer',
    'api_key',
    'apikey',
    'secret',
    'token',
    'eyj',
    'authorization',
  ];
  if (blocked.any(lower.contains)) return null;
  if (code.contains('@') || code.contains('http')) return null;
  if (RegExp(r'\d{11,}').hasMatch(code)) return null;
  if (RegExp(r'''[^\w\s.,:;!?()\-/ºª%'"]''', unicode: true).hasMatch(code)) {
    return null;
  }
  return code;
}

bool _isRasterImage(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  return bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
}

String _text(Object? value) {
  if (value is String) return value.trim();
  return '';
}

String? _optional(Object? value) {
  final text = _text(value);
  if (text.isEmpty) return null;
  return text;
}
