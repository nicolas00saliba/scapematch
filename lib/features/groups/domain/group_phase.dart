/// Onde o grupo está. Os quatro últimos existem para o portal da casa e o
/// pagamento dividido, que ainda não rodam neste app.
enum GroupPhase {
  forming,
  readyToReserve,
  awaitingHouse,
  confirmed,
  refused,
  awaitingPayments,
  cancelled,
}

/// Estados que só o portal da casa (ainda não ligado) grava.
bool isPortalPhase(GroupPhase phase) {
  return switch (phase) {
    GroupPhase.awaitingHouse ||
    GroupPhase.confirmed ||
    GroupPhase.refused ||
    GroupPhase.awaitingPayments => true,
    GroupPhase.forming ||
    GroupPhase.readyToReserve ||
    GroupPhase.cancelled => false,
  };
}
