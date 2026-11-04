import 'package:dominio/src/payment_exception.dart';
import 'package:dominio/src/payment_provider.dart';

/// Confirma na hora. A mesma chave devolve a mesma resposta.
class SimulatedPaymentProvider implements PaymentProvider {
  static const name = 'simulated';

  final Map<String, _Stored> _charges = {};
  final Map<String, _Stored> _refunds = {};

  @override
  Future<ChargeResult> chargeShare({
    required String shareId,
    required int amountCents,
    required PaymentMethodKind kind,
    required String idempotencyKey,
  }) {
    return Future.value(
      _once(
        store: _charges,
        idempotencyKey: idempotencyKey,
        shareOrChargeId: shareId,
        amountCents: amountCents,
        kind: kind,
        prefix: 'sim',
      ),
    );
  }

  @override
  Future<PixCharge> createPix({
    required String chargeId,
    required int amountCents,
    required String description,
    required String payerEmail,
    required String idempotencyKey,
    MarketplaceSplit? split,
  }) {
    return Future.value(
      PixCharge(
        provider: name,
        providerRef: 'sim_$idempotencyKey',
        amountCents: amountCents,
        qrCode: '00020126580014BR.GOV.BCB.PIX-SIM-$idempotencyKey',
        status: 'pending',
      ),
    );
  }

  @override
  Future<ChargeResult> refund({
    required String chargeId,
    required int amountCents,
    required String idempotencyKey,
  }) {
    return Future.value(
      _once(
        store: _refunds,
        idempotencyKey: idempotencyKey,
        shareOrChargeId: chargeId,
        amountCents: amountCents,
        prefix: 'sim-refund',
      ),
    );
  }

  ChargeResult _once({
    required Map<String, _Stored> store,
    required String idempotencyKey,
    required String shareOrChargeId,
    required int amountCents,
    required String prefix,
    PaymentMethodKind? kind,
  }) {
    final previous = store[idempotencyKey];
    if (previous != null) {
      if (previous.subjectId != shareOrChargeId ||
          previous.result.amountCents != amountCents) {
        throw IdempotencyConflictException();
      }
      return previous.result;
    }
    final result = ChargeResult(
      provider: name,
      providerRef: '${prefix}_$idempotencyKey',
      succeeded: true,
      amountCents: amountCents,
      kind: kind,
    );
    store[idempotencyKey] = _Stored(shareOrChargeId, result);
    return result;
  }
}

class _Stored {
  const _Stored(this.subjectId, this.result);

  final String subjectId;
  final ChargeResult result;
}
