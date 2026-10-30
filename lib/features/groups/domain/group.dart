import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Everything a group screen needs to draw one card or one detail page.
///
/// Names of the city, house, and room are copied onto the group on purpose.
/// The widget then does not have to join tables. A future Supabase
/// repository can do that join and return this same object.
class Group {
  const Group({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.houseId,
    required this.houseName,
    required this.neighborhood,
    required this.roomId,
    required this.roomName,
    required this.roomTheme,
    required this.roomCapacity,
    required this.durationMinutes,
    required this.difficulty,
    required this.slotId,
    required this.startsAt,
    required this.filledSpots,
    required this.totalSpots,
    required this.participants,
    required this.priceCents,
    this.gameType = GameTypes.escapeRoom,
    this.note = '',
    this.cancelledAt,
    this.minimumSpots = 2,
    this.closesAt,
    this.cancelWindow = GroupRules.refundDeadline,
    this.phaseOverride,
    this.streetAddress = '',
  });

  final String id;
  final String cityId;
  final String cityName;
  final String houseId;
  final String houseName;
  final String neighborhood;
  final String roomId;
  final String roomName;
  final String roomTheme;
  final int roomCapacity;
  final int durationMinutes;
  final Difficulty difficulty;
  final String slotId;
  final DateTime startsAt;

  /// People already in the group, including the creator.
  /// Cancelled seats are not included.
  final int filledSpots;

  /// How many people the group wants. This can be lower than [roomCapacity].
  final int totalSpots;
  final List<Participant> participants;

  /// Fictional price per person, in cents, copied from the room.
  final int priceCents;

  /// Tipo fictício do grupo. As salas ainda são todas de escape room.
  final String gameType;

  /// Optional note the creator can edit. Empty when they wrote nothing.
  final String note;

  /// Set when the creator deletes the group, or when it misses the close
  /// deadline. Null while the group is active.
  final DateTime? cancelledAt;

  /// Pessoas para o grupo ficar pronto para reservar. Vem da sala.
  final int minimumSpots;

  /// Prazo para atingir [minimumSpots]. Sem data, vale 1 h antes do início.
  final DateTime? closesAt;

  /// Janela de cancelamento com reembolso, copiada da casa.
  final Duration cancelWindow;

  /// Estados do portal (casa e pagamento). Nulo enquanto o app só forma o grupo.
  final GroupPhase? phaseOverride;

  /// Endereço fictício da sala, para o mapa.
  final String streetAddress;

  int get openSeats =>
      GroupRules.openSeats(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isFull =>
      !GroupRules.canJoin(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isAlmostFull =>
      GroupRules.isAlmostFull(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isCancelled => cancelledAt != null;

  /// Prazo gravado, ou 1 h antes do início quando o grupo não tem data.
  DateTime get closesAtResolved =>
      closesAt ?? startsAt.subtract(GroupRules.shortCloseLead);

  /// "Faltam X" e o prazo só enquanto o grupo ainda está se formando.
  bool showCloseDeadline(DateTime now) {
    return phaseAt(now) == GroupPhase.forming && now.isBefore(startsAt);
  }

  GroupPhase phaseAt(DateTime now) {
    final override = phaseOverride;
    if (override != null && isPortalPhase(override)) {
      return override;
    }
    if (isCancelled) {
      return GroupPhase.cancelled;
    }
    if (GroupRules.missedMinimum(
      alreadyCancelled: false,
      portalOwned: false,
      filledSpots: filledSpots,
      minimumSpots: minimumSpots,
      closesAt: closesAtResolved,
      startsAt: startsAt,
      now: now,
    )) {
      return GroupPhase.cancelled;
    }
    if (filledSpots >= minimumSpots) {
      return GroupPhase.readyToReserve;
    }
    return GroupPhase.forming;
  }

  int get spotsUntilClose {
    final missing = minimumSpots - filledSpots;
    return missing < 0 ? 0 : missing;
  }

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  int get confirmedCount =>
      participants.where((person) => person.isConfirmed).length;

  /// People who still hold a seat. Cancelled seats are not counted.
  int get seatedCount =>
      participants.where((person) => person.occupiesSeat).length;

  /// Floor for the size the creator may save.
  ///
  /// [filledSpots] can be higher than the roster when a group is marked
  /// full without one person per seat. The edit screen and the repository
  /// both use this number, so the stepper and the saved check cannot drift.
  int get occupiedSpots =>
      filledSpots > seatedCount ? filledSpots : seatedCount;

  bool get joinedByMe =>
      participants.any((person) => person.isLocalUser && person.occupiesSeat);

  Participant? participantForUser(String userId) {
    for (final person in participants) {
      if (person.userId == userId) {
        return person;
      }
    }
    return null;
  }

  bool createdBy(String userId) {
    return participants.any(
      (person) => person.isCreator && person.userId == userId,
    );
  }

  Group copyWith({
    int? filledSpots,
    int? totalSpots,
    List<Participant>? participants,
    String? note,
    DateTime? startsAt,
    DateTime? cancelledAt,
    String? gameType,
    int? minimumSpots,
    Object? closesAt = _absent,
    Duration? cancelWindow,
    Object? phaseOverride = _absent,
    String? streetAddress,
  }) {
    return Group(
      id: id,
      cityId: cityId,
      cityName: cityName,
      houseId: houseId,
      houseName: houseName,
      neighborhood: neighborhood,
      roomId: roomId,
      roomName: roomName,
      roomTheme: roomTheme,
      roomCapacity: roomCapacity,
      durationMinutes: durationMinutes,
      difficulty: difficulty,
      slotId: slotId,
      startsAt: startsAt ?? this.startsAt,
      filledSpots: filledSpots ?? this.filledSpots,
      totalSpots: totalSpots ?? this.totalSpots,
      participants: participants ?? this.participants,
      priceCents: priceCents,
      gameType: gameType ?? this.gameType,
      note: note ?? this.note,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      minimumSpots: minimumSpots ?? this.minimumSpots,
      closesAt: identical(closesAt, _absent)
          ? this.closesAt
          : closesAt as DateTime?,
      cancelWindow: cancelWindow ?? this.cancelWindow,
      phaseOverride: identical(phaseOverride, _absent)
          ? this.phaseOverride
          : phaseOverride as GroupPhase?,
      streetAddress: streetAddress ?? this.streetAddress,
    );
  }
}

/// Distinguishes "não passou o campo" de "passou nulo" no [Group.copyWith].
const _absent = Object();
