import 'package:dominio/dominio.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_statement.dart';

/// O que a tela da casa chama. A memória e o Supabase implementam isto.
abstract class PartnerDesk {
  Future<PartnerSnapshot> load(
    String houseId, {
    VenueFiscalProfile fiscal = demoHouseFiscal,
  });

  Future<AbsenceMark> markAbsence({
    required String houseId,
    required String groupId,
    required String playerId,
  });

  Future<String?> updatePrice({
    required String roomId,
    required int priceCents,
  });

  Future<TimeSlot> addSlot({
    required String roomId,
    required DateTime startsAt,
  });

  Future<String?> openSession({
    required String houseId,
    required String roomId,
    required DateTime startsAt,
    required int priceCents,
  });

  Future<String?> cancelSession({
    required String houseId,
    required String groupId,
    required String reason,
  });

  Future<String?> saveRoom({
    required String houseId,
    String? roomId,
    required String name,
    required Difficulty difficulty,
    required int durationMinutes,
    required int minimumPlayers,
    required int capacity,
    required int priceCents,
    required int accent,
    String theme = '',
    RoomCategory? category,
    List<RoomPicture>? pictures,
  });
}

/// Leitura da casa. O livro e o catálogo são os mesmos do app do jogador.
class PartnerRepository implements PartnerDesk {
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

  @override
  Future<PartnerSnapshot> load(
    String houseId, {
    VenueFiscalProfile fiscal = demoHouseFiscal,
  }) async {
    final house = database.houseById(houseId);
    if (house == null) {
      throw StateError('Casa não encontrada.');
    }
    await groups.materializeHouse(houseId);
    final now = clock.now();
    final houseGroups =
        database.groups.where((group) => group.houseId == houseId).toList()
          ..sort((a, b) => _byWhen(a, b, now));
    final rooms =
        database.rooms.where((room) => room.houseId == houseId).toList()
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
      invoices: _invoices(
        houseId: houseId,
        houseName: house.name,
        groups: houseGroups,
        fiscal: fiscal,
      ),
      fiscal: fiscal,
    );
  }

  List<FiscalInvoiceView> _invoices({
    required String houseId,
    required String houseName,
    required List<Group> groups,
    required VenueFiscalProfile fiscal,
  }) {
    final notes = <FiscalInvoiceView>[];
    for (final reservation in this.groups.payments.reservations) {
      if (reservation.houseId != houseId) {
        continue;
      }
      Group? group;
      for (final candidate in groups) {
        if (candidate.id == reservation.groupId) {
          group = candidate;
          break;
        }
      }
      if (group == null) {
        continue;
      }
      for (final share in reservation.shares) {
        if (share.status != ShareStatus.paid) {
          continue;
        }
        notes.addAll(
          planChargeInvoices(
            share: PaidShare(
              chargeId: share.id,
              groupId: group.id,
              venueId: houseId,
              venueName: houseName,
              playerId: share.playerId,
              playerName: _playerName(group, share.playerId),
              amountCents: share.amountCents,
              commissionCents: share.commissionCents,
              paidAt: group.startsAt,
            ),
            venue: fiscal,
          ),
        );
      }
    }
    notes.sort((a, b) {
      final byTime = b.paidAt.compareTo(a.paidAt);
      if (byTime != 0) {
        return byTime;
      }
      final byPlayer = a.playerName.compareTo(b.playerName);
      if (byPlayer != 0) {
        return byPlayer;
      }
      return a.kind == FiscalInvoiceKind.service ? -1 : 1;
    });
    return notes;
  }

  String _playerName(Group group, String playerId) {
    for (final person in group.participants) {
      if (person.userId == playerId || person.id == playerId) {
        return person.displayName;
      }
    }
    return playerId;
  }

  /// Primeira falta avisa. A terceira bloqueia. Repetir o grupo não soma.
  @override
  Future<AbsenceMark> markAbsence({
    required String houseId,
    required String groupId,
    required String playerId,
  }) async {
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

  @override
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

  @override
  Future<TimeSlot> addSlot({
    required String roomId,
    required DateTime startsAt,
  }) {
    return catalog.addSlot(roomId, startsAt);
  }

  /// Abre uma sessão vazia. O jogador vê o grupo e o horário na sala.
  @override
  Future<String?> openSession({
    required String houseId,
    required String roomId,
    required DateTime startsAt,
    required int priceCents,
  }) async {
    final house = database.houseById(houseId);
    final room = database.roomById(roomId);
    final city = house == null ? null : database.cityById(house.cityId);
    if (house == null ||
        city == null ||
        room == null ||
        room.houseId != house.id) {
      return 'Sala não encontrada nesta casa.';
    }
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    if (!isHouseHour(startsAt)) {
      return 'Escolha 14:00, 16:30, 19:00 ou 21:00.';
    }
    final now = clock.now();
    if (!startsAt.isAfter(now)) {
      return 'Esse horário já passou.';
    }
    if (GroupRules.tooCloseToCreate(startsAt: startsAt, now: now)) {
      return 'Falta menos de 1 h. Escolha outro horário.';
    }
    final taken = database.groups.any(
      (group) =>
          !group.isCancelled &&
          group.roomId == room.id &&
          group.startsAt == startsAt,
    );
    if (taken) {
      return 'Essa sala já tem sessão nesse horário.';
    }
    final slot = database.addSlot(roomId: room.id, startsAt: startsAt);
    database.groups.add(
      Group(
        id: database.nextGroupId(),
        cityId: city.id,
        cityName: city.name,
        houseId: house.id,
        houseName: house.name,
        neighborhood: house.neighborhood,
        roomId: room.id,
        roomName: room.name,
        roomTheme: room.theme,
        roomCapacity: room.capacity,
        roomMinimum: room.minimumPlayers,
        durationMinutes: room.durationMinutes,
        difficulty: room.difficulty,
        slotId: slot.id,
        startsAt: slot.startsAt,
        filledSpots: 0,
        totalSpots: room.capacity,
        priceCents: priceCents,
        minimumSpots: room.minimumPlayers,
        closesAt: GroupRules.closeDeadline(startsAt: slot.startsAt, now: now),
        cancelWindow: room.cancelWindow,
        streetAddress: house.streetAddress,
        coverAsset: roomCategoryImage(room.category),
        participants: const [],
      ),
    );
    return null;
  }

  @override
  Future<String?> cancelSession({
    required String houseId,
    required String groupId,
    required String reason,
  }) {
    return groups.cancelForHouse(
      houseId: houseId,
      groupId: groupId,
      reason: reason,
    );
  }

  @override
  Future<String?> saveRoom({
    required String houseId,
    String? roomId,
    required String name,
    required Difficulty difficulty,
    required int durationMinutes,
    required int minimumPlayers,
    required int capacity,
    required int priceCents,
    required int accent,
    String theme = '',
    RoomCategory? category,
    List<RoomPicture>? pictures,
  }) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      return 'Dê um nome para a sala.';
    }
    final story = theme.trim();
    if (story.isNotEmpty && (story.length < 8 || story.length > 180)) {
      return 'A história fica entre 8 e 180 caracteres.';
    }
    if (minimumPlayers < 2 || capacity < minimumPlayers || capacity > 12) {
      return 'O mínimo e o máximo precisam caber na sala.';
    }
    if (durationMinutes < 30 || durationMinutes > 240) {
      return 'A duração fica entre 30 e 240 minutos.';
    }
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    if (roomId == null) {
      final house = database.houseById(houseId);
      if (house == null) {
        return 'Casa não encontrada.';
      }
      database.addRoom(
        EscapeRoom(
          id: 'room-$houseId-${database.rooms.length + 1}',
          houseId: houseId,
          name: trimmed,
          theme: story.isEmpty ? 'Sala aberta pela casa' : story,
          category: category ?? RoomCategory.mystery,
          pictures: pictures ?? const [],
          capacity: capacity,
          durationMinutes: durationMinutes,
          difficulty: difficulty,
          priceCents: priceCents,
          minimumPlayers: minimumPlayers,
          accent: accent,
        ),
      );
      return null;
    }
    final room = database.roomById(roomId);
    if (room == null || room.houseId != houseId) {
      return 'Sala não encontrada nesta casa.';
    }
    database.replaceRoom(
      room.copyWith(
        name: trimmed,
        theme: story.isEmpty ? room.theme : story,
        category: category ?? room.category,
        difficulty: difficulty,
        durationMinutes: durationMinutes,
        minimumPlayers: minimumPlayers,
        capacity: capacity,
        priceCents: priceCents,
        accent: accent,
        pictures: pictures ?? room.pictures,
      ),
    );
    return null;
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

bool isHouseHour(DateTime startsAt) {
  const hours = <(int, int)>[(14, 0), (16, 30), (19, 0), (21, 0)];
  for (final (hour, minute) in hours) {
    if (startsAt.hour == hour && startsAt.minute == minute) {
      return true;
    }
  }
  return false;
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
