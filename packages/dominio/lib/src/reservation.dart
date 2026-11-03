/// Onde a parte do jogador está.
enum ShareStatus { pending, paid, failed, refunded }

/// Leitura da reserva a partir das partes. Não é uma coluna solta.
enum ReservationStatus { open, partial, paid, refunded }

/// Uma parte. Comissão e líquido nascem com a reserva e não seguem a taxa nova.
class ReservationShare {
  const ReservationShare({
    required this.id,
    required this.playerId,
    required this.amountCents,
    required this.commissionCents,
    required this.netCents,
    required this.status,
  });

  final String id;
  final String playerId;
  final int amountCents;
  final int commissionCents;
  final int netCents;
  final ShareStatus status;

  ReservationShare copyWith({ShareStatus? status}) {
    return ReservationShare(
      id: id,
      playerId: playerId,
      amountCents: amountCents,
      commissionCents: commissionCents,
      netCents: netCents,
      status: status ?? this.status,
    );
  }
}

/// Reserva com a taxa vigente no momento em que foi aberta.
class Reservation {
  Reservation({
    required this.id,
    required this.groupId,
    required this.houseId,
    required this.commissionBps,
    required List<ReservationShare> shares,
  }) : shares = List.unmodifiable(shares);

  final String id;
  final String groupId;
  final String houseId;

  /// Cópia da taxa. Mudar a configuração não reescreve este número.
  final int commissionBps;
  final List<ReservationShare> shares;

  int get grossCents => shares.fold(0, (sum, share) => sum + share.amountCents);

  int get commissionCents =>
      shares.fold(0, (sum, share) => sum + share.commissionCents);

  int get netCents => shares.fold(0, (sum, share) => sum + share.netCents);

  ReservationStatus get status {
    if (shares.every((share) => share.status == ShareStatus.refunded)) {
      return ReservationStatus.refunded;
    }
    if (shares.every((share) => share.status == ShareStatus.paid)) {
      return ReservationStatus.paid;
    }
    if (shares.any(
      (share) =>
          share.status == ShareStatus.paid ||
          share.status == ShareStatus.refunded,
    )) {
      return ReservationStatus.partial;
    }
    return ReservationStatus.open;
  }

  Reservation copyWithShare(ReservationShare share) {
    return Reservation(
      id: id,
      groupId: groupId,
      houseId: houseId,
      commissionBps: commissionBps,
      shares: [
        for (final current in shares)
          if (current.id == share.id) share else current,
      ],
    );
  }
}
