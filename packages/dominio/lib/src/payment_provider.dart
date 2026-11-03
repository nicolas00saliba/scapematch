/// Forma que o jogador escolhe. Os dois caminhos são simulados nesta fase.
enum PaymentMethodKind { pix, card }

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
}
