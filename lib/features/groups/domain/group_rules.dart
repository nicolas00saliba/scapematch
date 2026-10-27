/// Product rules that do not depend on Flutter or on where data is stored.
///
/// Screens and repositories both call these functions. When the fake data
/// source is replaced, the rules stay here and do not need to be rewritten.
///
/// Provisional product choices (free join, the almost-full limit, one group
/// per room and time) are recorded in `docs/DECISOES.md`.
class GroupRules {
  const GroupRules._();

  /// "Quase cheios" means the group can still be joined and only a few
  /// seats are left. Change this constant to retune the filter.
  /// A full group is excluded: the filter is for people who can still enter.
  static const almostFullMaxOpenSeats = 2;

  /// The creator is already seated, so the form must ask for at least one
  /// more person. A group of one is not a group.
  static const minExtraSpots = 1;

  static int openSeats({required int filledSpots, required int totalSpots}) {
    return totalSpots - filledSpots;
  }

  static bool canJoin({required int filledSpots, required int totalSpots}) {
    return filledSpots < totalSpots;
  }

  static bool isAlmostFull({
    required int filledSpots,
    required int totalSpots,
  }) {
    final open = openSeats(filledSpots: filledSpots, totalSpots: totalSpots);
    return open >= 1 && open <= almostFullMaxOpenSeats;
  }

  /// Extra seats the creator may ask for once a room is known.
  ///
  /// The creator already occupies one seat, so the ceiling is
  /// `roomCapacity - 1`. Null means no room has been chosen yet: the form
  /// must not invent a fixed ceiling such as 12.
  static int? maxExtraSpots({required int? roomCapacity}) {
    if (roomCapacity == null) {
      return null;
    }
    return roomCapacity - 1;
  }

  /// Pulls [value] into the allowed range.
  ///
  /// The floor is [minExtraSpots]. The ceiling is [maxExtraSpots] when a
  /// room is known. Without a room, only the floor applies.
  static int clampExtraSpots(int value, {int? roomCapacity}) {
    var spots = value < minExtraSpots ? minExtraSpots : value;
    final max = maxExtraSpots(roomCapacity: roomCapacity);
    if (max != null && max >= minExtraSpots && spots > max) {
      spots = max;
    }
    return spots;
  }

  /// [extraSpots] is how many people the creator is still looking for.
  /// The creator already takes one seat, so creator + extraSpots must fit
  /// in the room.
  static GroupSizeValidation validateGroupSize({
    required int extraSpots,
    required int roomCapacity,
  }) {
    if (extraSpots < minExtraSpots) {
      return GroupSizeValidation.belowMinimum;
    }
    if (1 + extraSpots > roomCapacity) {
      return GroupSizeValidation.exceedsRoomCapacity;
    }
    return GroupSizeValidation.valid;
  }

  /// Two groups cannot book the same room at the same start time.
  ///
  /// A different room at that time is fine. The same room at another time
  /// is fine. The comparison is the clock time, not the slot id, so two
  /// slot records that share a start still conflict.
  static bool roomAndTimeTaken({
    required String roomId,
    required DateTime startsAt,
    required Iterable<({String roomId, DateTime startsAt})> existing,
  }) {
    for (final session in existing) {
      if (session.roomId == roomId && session.startsAt == startsAt) {
        return true;
      }
    }
    return false;
  }
}

enum GroupSizeValidation { valid, belowMinimum, exceedsRoomCapacity }
