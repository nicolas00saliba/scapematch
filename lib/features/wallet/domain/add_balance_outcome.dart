/// Resultado de uma tentativa de recarga. Nesta versão só existe a recusa.
enum AddBalanceFailure { notAvailable }

/// A recarga ainda não existe. O repositório fictício devolve isto e não
/// mexe no saldo. O gateway real usa a mesma forma, com a chave de
/// idempotência, para não cobrar duas vezes.
class AddBalanceOutcome {
  const AddBalanceOutcome.unavailable()
    : failure = AddBalanceFailure.notAvailable;

  final AddBalanceFailure? failure;

  bool get applied => failure == null;
}
