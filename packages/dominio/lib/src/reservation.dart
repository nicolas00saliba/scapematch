/// Onde a parte do jogador está.
///
/// [reserved] é a pré-autorização: o valor está separado, ainda não entrou
/// no extrato. [paid] é a captura, quando o grupo fecha. [released] devolve
/// a reserva sem cobrança.
enum ShareStatus {
  pending,
  reserved,
  awaitingConfirmation,
  paid,
  failed,
  refunded,
  released,
}

/// Leitura da reserva a partir das partes. Não é uma coluna solta.
enum ReservationStatus { open, held, partial, paid, refunded, released }

/// Preço por pessoa, ou um total fixo do grupo dividido entre quem ficou.
enum PriceMode { perPerson, fixedGroup }

/// Uma parte. Comissão e líquido nascem com a reserva e não seguem a taxa nova.
class ReservationShare {
  const ReservationShare({
    required this.id,
    required this.playerId,
    required this.amountCents,
    required this.commissionCents,
    required this.netCents,
    required this.status,
    this.proposedAmountCents,
    this.proposedCommissionCents,
    this.proposedNetCents,
  });

  final String id;
  final String playerId;
  final int amountCents;
  final int commissionCents;
  final int netCents;
  final ShareStatus status;

  /// Novo valor, quando o grupo de preço fixo fecha com menos gente.
  final int? proposedAmountCents;
  final int? proposedCommissionCents;
  final int? proposedNetCents;

  ReservationShare copyWith({
    ShareStatus? status,
    int? amountCents,
    int? commissionCents,
    int? netCents,
    int? proposedAmountCents,
    int? proposedCommissionCents,
    int? proposedNetCents,
    bool clearProposal = false,
  }) {
    return ReservationShare(
      id: id,
      playerId: playerId,
      amountCents: amountCents ?? this.amountCents,
      commissionCents: commissionCents ?? this.commissionCents,
      netCents: netCents ?? this.netCents,
      status: status ?? this.status,
      proposedAmountCents: clearProposal
          ? null
          : proposedAmountCents ?? this.proposedAmountCents,
      proposedCommissionCents: clearProposal
          ? null
          : proposedCommissionCents ?? this.proposedCommissionCents,
      proposedNetCents: clearProposal
          ? null
          : proposedNetCents ?? this.proposedNetCents,
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
    required this.totalCents,
    required List<ReservationShare> shares,
    this.priceMode = PriceMode.perPerson,
  }) : shares = List.unmodifiable(shares);

  final String id;
  final String groupId;
  final String houseId;

  /// Cópia da taxa. Mudar a configuração não reescreve este número.
  final int commissionBps;

  /// Total da reserva na abertura. No preço fixo, fechar com menos gente
  /// divide este mesmo total.
  final int totalCents;
  final PriceMode priceMode;
  final List<ReservationShare> shares;

  int get grossCents => shares.fold(0, (sum, share) => sum + share.amountCents);

  int get commissionCents =>
      shares.fold(0, (sum, share) => sum + share.commissionCents);

  int get netCents => shares.fold(0, (sum, share) => sum + share.netCents);

  bool get needsConfirmation => shares.any(
    (share) => share.status == ShareStatus.awaitingConfirmation,
  );

  ReservationStatus get status {
    if (shares.every((share) => share.status == ShareStatus.refunded)) {
      return ReservationStatus.refunded;
    }
    if (shares.every((share) => share.status == ShareStatus.released)) {
      return ReservationStatus.released;
    }
    if (shares.every((share) => share.status == ShareStatus.paid)) {
      return ReservationStatus.paid;
    }
    if (shares.isNotEmpty &&
        shares.every((share) => share.status == ShareStatus.reserved)) {
      return ReservationStatus.held;
    }
    if (shares.any(
      (share) =>
          share.status == ShareStatus.paid ||
          share.status == ShareStatus.reserved ||
          share.status == ShareStatus.refunded ||
          share.status == ShareStatus.released,
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
      totalCents: totalCents,
      priceMode: priceMode,
      shares: [
        for (final current in shares)
          if (current.id == share.id) share else current,
      ],
    );
  }

  Reservation copyWithShares(List<ReservationShare> shares) {
    return Reservation(
      id: id,
      groupId: groupId,
      houseId: houseId,
      commissionBps: commissionBps,
      totalCents: totalCents,
      priceMode: priceMode,
      shares: shares,
    );
  }
}
