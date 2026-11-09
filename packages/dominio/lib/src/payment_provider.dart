/// Forma que o jogador escolhe.
enum PaymentMethodKind { pix, card }

/// Repasse para a subconta da casa. No Asaas o split usa o walletId;
/// a comissão da EscapeMatch fica na conta que cria a cobrança.
class MarketplaceSplit {
  const MarketplaceSplit({
    required this.sellerId,
    required this.applicationFeeCents,
  });

  /// Conta da casa no gateway (collector, seller, recipient).
  final String sellerId;

  /// O que fica com a plataforma, em centavos.
  final int applicationFeeCents;
}

/// Pix gerado pelo provedor. [succeeded] não existe: o QR nasce pendente.
class PixCharge {
  const PixCharge({
    required this.provider,
    required this.providerRef,
    required this.amountCents,
    required this.qrCode,
    required this.status,
    this.qrCodeBase64,
  });

  final String provider;
  final String providerRef;
  final int amountCents;

  /// Copia-e-cola.
  final String qrCode;
  final String? qrCodeBase64;

  /// `pending`, `approved`, `rejected` ou `cancelled`.
  final String status;

  bool get isPending => status == 'pending';
}

/// Transporte até a Edge Function. A chave do Asaas não passa por aqui.
abstract class PixTransport {
  Future<Map<String, dynamic>> postPix(Map<String, dynamic> body);
}

/// Resultado de uma cobrança ou de um estorno no provedor.
class ChargeResult {
  const ChargeResult({
    required this.provider,
    required this.providerRef,
    required this.succeeded,
    required this.amountCents,
    this.kind,
  });

  final String provider;
  final String providerRef;
  final bool succeeded;
  final int amountCents;
  final PaymentMethodKind? kind;
}

/// Porta da cobrança. A tela fala com o livro; o livro fala com isto.
abstract class PaymentProvider {
  Future<ChargeResult> chargeShare({
    required String shareId,
    required int amountCents,
    required PaymentMethodKind kind,
    required String idempotencyKey,
  });

  Future<ChargeResult> refund({
    required String chargeId,
    required int amountCents,
    required String idempotencyKey,
  });

  /// Gera o QR do Pix. [split] é o gancho do marketplace e pode ser nulo.
  Future<PixCharge> createPix({
    required String chargeId,
    required int amountCents,
    required String description,
    required String payerEmail,
    required String idempotencyKey,
    MarketplaceSplit? split,
  });
}
