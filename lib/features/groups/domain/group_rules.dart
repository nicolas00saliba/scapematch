/// Product rules that do not depend on Flutter or on where data is stored.
///
/// Screens and repositories both call these functions. When the fake data
/// source is replaced, the rules stay here and do not need to be rewritten.
class GroupRules {
  const GroupRules._();

  /// "Quase cheios" means the group can still be joined and only a few
  /// seats are left. This version uses 1 or 2 open seats.
  /// A full group is excluded: the filter is for people who can still enter.
  static const almostFullMaxOpenSeats = 2;

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

  /// [extraSpots] is how many people the creator is still looking for.
  /// The creator already takes one seat, so creator + extraSpots must fit
  /// in the room.
  static GroupSizeValidation validateGroupSize({
    required int extraSpots,
    required int roomCapacity,
  }) {
    if (extraSpots < 1) {
      return GroupSizeValidation.belowMinimum;
    }
    if (1 + extraSpots > roomCapacity) {
      return GroupSizeValidation.exceedsRoomCapacity;
    }
    return GroupSizeValidation.valid;
  }
}

enum GroupSizeValidation { valid, belowMinimum, exceedsRoomCapacity }
