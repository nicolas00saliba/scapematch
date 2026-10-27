import 'package:scapematch/features/catalog/domain/difficulty.dart';
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
    this.note = '',
    this.cancelledAt,
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

  /// Optional note the creator can edit. Empty when they wrote nothing.
  final String note;

  /// Set when the creator deletes the group. Null while the group is active.
  final DateTime? cancelledAt;

  int get openSeats =>
      GroupRules.openSeats(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isFull =>
      !GroupRules.canJoin(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isAlmostFull =>
      GroupRules.isAlmostFull(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isCancelled => cancelledAt != null;

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
      note: note ?? this.note,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }
}
