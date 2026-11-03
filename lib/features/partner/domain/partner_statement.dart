import 'package:dominio/dominio.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Uma linha do extrato da casa. Bruto = líquido + comissão.
class StatementLine {
  const StatementLine({
    required this.chargeId,
    required this.title,
    required this.grossCents,
    required this.commissionCents,
    required this.netCents,
    required this.refund,
  });

  final String chargeId;
  final String title;
  final int grossCents;
  final int commissionCents;
  final int netCents;
  final bool refund;
}

/// Soma o que ainda está só reservado. Não entra no saldo.
int reservedHoldCents(Iterable<Reservation> reservations, String houseId) {
  var sum = 0;
  for (final reservation in reservations) {
    if (reservation.houseId != houseId) {
      continue;
    }
    for (final share in reservation.shares) {
      if (share.status == ShareStatus.reserved ||
          share.status == ShareStatus.awaitingConfirmation) {
        sum += share.amountCents;
      }
    }
  }
  return sum;
}

/// Agrupa o livro por cobrança. A ordem é a da captura, da mais nova à antiga.
List<StatementLine> buildStatement({
  required List<LedgerEntry> entries,
  required List<Reservation> reservations,
  required List<Group> groups,
  required String houseId,
}) {
  final order = <String>[];
  final batches = <String, List<LedgerEntry>>{};
  for (final entry in entries) {
    if (entry.houseId != houseId) {
      continue;
    }
    final batch = batches.putIfAbsent(entry.chargeId, () {
      order.add(entry.chargeId);
      return <LedgerEntry>[];
    });
    batch.add(entry);
  }
  final lines = <StatementLine>[];
  for (final chargeId in order.reversed) {
    final batch = batches[chargeId]!;
    var net = 0;
    var commission = 0;
    var refund = false;
    for (final entry in batch) {
      final sign = entry.direction == LedgerDirection.credit ? 1 : -1;
      switch (entry.kind) {
        case LedgerKind.houseNet:
        case LedgerKind.houseRefund:
          net += sign * entry.amountCents;
        case LedgerKind.commission:
        case LedgerKind.commissionRefund:
          commission += sign * entry.amountCents;
      }
      if (entry.direction == LedgerDirection.debit) {
        refund = true;
      }
    }
    final first = batch.first;
    lines.add(
      StatementLine(
        chargeId: chargeId,
        title: _title(
          shareId: first.shareId,
          reservationId: first.reservationId,
          reservations: reservations,
          groups: groups,
        ),
        grossCents: net + commission,
        commissionCents: commission,
        netCents: net,
        refund: refund,
      ),
    );
  }
  return lines;
}

String _title({
  required String shareId,
  required String reservationId,
  required List<Reservation> reservations,
  required List<Group> groups,
}) {
  Reservation? reservation;
  for (final item in reservations) {
    if (item.id == reservationId) {
      reservation = item;
      break;
    }
  }
  var playerId = '';
  if (reservation != null) {
    for (final share in reservation.shares) {
      if (share.id == shareId) {
        playerId = share.playerId;
        break;
      }
    }
  }
  Group? group;
  final groupId = reservation?.groupId ?? reservationId;
  for (final item in groups) {
    if (item.id == groupId) {
      group = item;
      break;
    }
  }
  var name = 'Jogador';
  if (group != null && playerId.isNotEmpty) {
    for (final person in group.participants) {
      if (_matches(person, playerId)) {
        name = person.displayName;
        break;
      }
    }
  }
  final room = group?.roomName ?? 'Reserva';
  return '$name · $room';
}

bool _matches(Participant person, String playerId) {
  if (person.id == playerId) {
    return true;
  }
  final userId = person.userId;
  return userId != null && userId.isNotEmpty && userId == playerId;
}
