import 'package:dominio/dominio.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch/features/partner/domain/partner_statement.dart';

/// Leitura da casa. O livro e o catálogo são os mesmos do app do jogador.
class PartnerRepository {
  PartnerRepository({
    required this.groups,
    required this.catalog,
    required this.database,
    required this.clock,
  });

  final FakeGroupRepository groups;
  final FakeCatalogRepository catalog;
  final FakeDatabase database;
  final Clock clock;

  Future<PartnerSnapshot> load(String houseId) async {
    final house = database.houseById(houseId);
    if (house == null) {
      throw StateError('Casa não encontrada.');
    }
    await groups.materializeHouse(houseId);
    final now = clock.now();
    final houseGroups = database.groups
        .where((group) => group.houseId == houseId)
        .toList()
      ..sort((a, b) => _byWhen(a, b, now));
    final rooms = database.rooms
        .where((room) => room.houseId == houseId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final roomIds = rooms.map((room) => room.id).toSet();
    final slotsByRoom = <String, List<TimeSlot>>{};
    for (final slot in database.slots) {
      if (!roomIds.contains(slot.roomId)) {
        continue;
      }
      slotsByRoom.putIfAbsent(slot.roomId, () => []).add(slot);
    }
    for (final slots in slotsByRoom.values) {
      slots.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    final reservations = groups.payments.reservations
        .where((reservation) => reservation.houseId == houseId)
        .toList();
    final moneyByGroup = {
      for (final group in houseGroups)
        group.id: _moneyFor(group.id, reservations),
    };
    final lines = buildStatement(
      entries: groups.payments.entries,
      reservations: reservations,
      groups: houseGroups,
      houseId: houseId,
    );
    final counts = <String, int>{};
    final marks = <String>{};
    final standings = <String, AbsenceStanding>{};
    for (final record in groups.absences.records) {
      if (record.houseId != houseId) {
        continue;
      }
      marks.add('${record.groupId}|${record.playerId}');
      counts[record.playerId] = groups.absences.countOf(record.playerId);
      standings[record.playerId] = groups.absences.standingOf(record.playerId);
    }
    return PartnerSnapshot(
      house: house,
      now: now,
      grossCents: lines.fold(0, (sum, line) => sum + line.grossCents),
      commissionCents: lines.fold(0, (sum, line) => sum + line.commissionCents),
      netCents: groups.payments.houseBalance(houseId),
      reservedCents: reservedHoldCents(reservations, houseId),
      lines: lines,
      moneyByGroup: moneyByGroup,
      groups: houseGroups,
      rooms: rooms,
      slotsByRoom: slotsByRoom,
      absenceCounts: counts,
      absenceMarks: marks,
      standings: standings,
    );
  }

  /// Primeira falta avisa. A terceira bloqueia. Repetir o grupo não soma.
  AbsenceMark markAbsence({
    required String houseId,
    required String groupId,
    required String playerId,
  }) {
    final group = _group(houseId, groupId);
    if (group == null) {
      return const AbsenceRejected('Grupo não encontrado nesta casa.');
    }
    if (group.isCancelled) {
      return const AbsenceRejected('Grupo cancelado não registra falta.');
    }
    if (clock.now().isBefore(group.startsAt)) {
      return const AbsenceRejected('A sessão ainda não começou.');
    }
    final seated = group.participants.any(
      (person) => person.occupiesSeat && _playerId(person) == playerId,
    );
    if (!seated) {
      return const AbsenceRejected('Essa pessoa não está no grupo.');
    }
    final standing = groups.absences.markAbsent(
      playerId: playerId,
      groupId: groupId,
      houseId: houseId,
    );
    return AbsenceMarked(standing, groups.absences.countOf(playerId));
  }

  Future<String?> updatePrice({
    required String roomId,
    required int priceCents,
  }) async {
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    await catalog.updatePrice(roomId, priceCents);
    return null;
  }

  Future<TimeSlot> addSlot({
    required String roomId,
    required DateTime startsAt,
  }) {
    return catalog.addSlot(roomId, startsAt);
  }

  Group? _group(String houseId, String groupId) {
    for (final group in database.groups) {
      if (group.id == groupId && group.houseId == houseId) {
        return group;
      }
    }
    return null;
  }
}

GroupMoney _moneyFor(String groupId, List<Reservation> reservations) {
  Reservation? reservation;
  for (final item in reservations) {
    if (item.groupId == groupId || item.id == groupId) {
      reservation = item;
      break;
    }
  }
  if (reservation == null) {
    return GroupMoney.zero;
  }
  var gross = 0;
  var commission = 0;
  var net = 0;
  for (final share in reservation.shares) {
    if (share.status != ShareStatus.reserved &&
        share.status != ShareStatus.awaitingConfirmation &&
        share.status != ShareStatus.paid) {
      continue;
    }
    gross += share.amountCents;
    commission += share.commissionCents;
    net += share.netCents;
  }
  return GroupMoney(
    grossCents: gross,
    commissionCents: commission,
    netCents: net,
  );
}

int _byWhen(Group a, Group b, DateTime now) {
  int rank(Group group) {
    if (group.isCancelled) {
      return 2;
    }
    if (group.startsAt.isBefore(now)) {
      return 1;
    }
    return 0;
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) {
    return byRank;
  }
  return a.startsAt.compareTo(b.startsAt);
}

String playerIdOf(Participant person) => _playerId(person);

String _playerId(Participant person) {
  final userId = person.userId;
  if (userId != null && userId.isNotEmpty) {
    return userId;
  }
  return person.id;
}

sealed class AbsenceMark {
  const AbsenceMark();
}

class AbsenceMarked extends AbsenceMark {
  const AbsenceMarked(this.standing, this.count);

  final AbsenceStanding standing;
  final int count;
}

class AbsenceRejected extends AbsenceMark {
  const AbsenceRejected(this.message);

  final String message;
}
