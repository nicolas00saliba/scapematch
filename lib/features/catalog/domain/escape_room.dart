import 'package:scapematch/features/catalog/domain/difficulty.dart';

/// One playable room. [capacity] is the room limit, not the group size.
class EscapeRoom {
  const EscapeRoom({
    required this.id,
    required this.houseId,
    required this.name,
    required this.theme,
    required this.capacity,
    required this.durationMinutes,
    required this.difficulty,
    required this.priceCents,
  });

  final String id;
  final String houseId;
  final String name;
  final String theme;

  /// Maximum number of players the room allows, including the creator.
  final int capacity;
  final int durationMinutes;
  final Difficulty difficulty;

  /// Fictional price per person, in cents. Nothing is charged.
  final int priceCents;
}
