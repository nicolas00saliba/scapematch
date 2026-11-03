/// Conta que recebe o lançamento.
enum LedgerAccount { house, platform }

/// Sentido do lançamento. Estorno é um débito novo, não uma edição.
enum LedgerDirection { credit, debit }

/// Motivo da linha. Estorno tem motivo próprio.
enum LedgerKind { houseNet, commission, houseRefund, commissionRefund }

/// Uma linha de extrato. O saldo é a soma. O valor é sempre positivo.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.houseId,
    required this.reservationId,
    required this.shareId,
    required this.chargeId,
    required this.account,
    required this.direction,
    required this.kind,
    required this.amountCents,
  });

  final String id;
  final String houseId;
  final String reservationId;
  final String shareId;
  final String chargeId;
  final LedgerAccount account;
  final LedgerDirection direction;
  final LedgerKind kind;
  final int amountCents;

  int get signedCents =>
      direction == LedgerDirection.credit ? amountCents : -amountCents;
}

/// Soma das linhas de uma conta. A casa filtra pelo próprio id.
int ledgerBalance(
  Iterable<LedgerEntry> entries, {
  required LedgerAccount account,
  String? houseId,
}) {
  var sum = 0;
  for (final entry in entries) {
    if (entry.account != account) {
      continue;
    }
    if (houseId != null && entry.houseId != houseId) {
      continue;
    }
    sum += entry.signedCents;
  }
  return sum;
}
