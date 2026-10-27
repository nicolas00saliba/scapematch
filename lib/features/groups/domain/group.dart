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
  final int filledSpots;

  /// How many people the group wants. This can be lower than [roomCapacity].
  final int totalSpots;
  final List<Participant> participants;

  int get openSeats =>
      GroupRules.openSeats(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isFull =>
      !GroupRules.canJoin(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get isAlmostFull =>
      GroupRules.isAlmostFull(filledSpots: filledSpots, totalSpots: totalSpots);

  bool get joinedByMe => participants.any((person) => person.isLocalUser);

  Group copyWith({int? filledSpots, List<Participant>? participants}) {
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
      startsAt: startsAt,
      filledSpots: filledSpots ?? this.filledSpots,
      totalSpots: totalSpots,
      participants: participants ?? this.participants,
    );
  }
}
