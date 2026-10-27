import 'package:scapematch/features/groups/domain/attendance.dart';

/// Product rules that do not depend on Flutter or on where data is stored.
///
/// Screens and repositories both call these functions. When the fake data
/// source is replaced, the rules stay here and do not need to be rewritten.
///
/// Provisional product choices (free join, the almost-full limit, one group
/// per room and time, the refund window) are recorded in `docs/DECISOES.md`.
class GroupRules {
  const GroupRules._();

  /// "Quase cheios" means the group can still be joined and only a few
  /// seats are left. Change this constant to retune the filter.
  /// A full group is excluded: the filter is for people who can still enter.
  static const almostFullMaxOpenSeats = 2;

  /// The creator is already seated, so the form must ask for at least one
  /// more person. A group of one is not a group.
  static const minExtraSpots = 1;

  /// Creator plus at least one other person.
  static const minGroupSize = minExtraSpots + 1;

  /// Leaving at least this long before the start refunds the simulated
  /// payment. Exactly this duration still refunds. Less than this does not.
  /// The organizer cancelling or removing someone always refunds, and that
  /// path does not read this constant.
  static const refundDeadline = Duration(hours: 2);

  /// Creator note stored on the group. Longer text is rejected.
  static const maxNoteLength = 280;

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
      // == also compares isUtc, so the same instant stored as UTC and as
      // local would look free. The room is taken when the moments match.
      if (session.roomId == roomId &&
          session.startsAt.isAtSameMomentAs(startsAt)) {
        return true;
      }
    }
    return false;
  }

  /// True once [now] is the start instant or later.
  static bool hasStarted({required DateTime startsAt, required DateTime now}) {
    return !now.isBefore(startsAt);
  }

  /// True once [now] is the end instant or later.
  static bool hasEnded({required DateTime endsAt, required DateTime now}) {
    return !now.isBefore(endsAt);
  }

  /// Volunteer cancellation refunds when the session is at least
  /// [refundDeadline] away. Exactly [refundDeadline] refunds. A session
  /// that starts in less than that, or that already started, does not.
  static bool refundsOnParticipantCancel({
    required DateTime startsAt,
    required DateTime now,
  }) {
    return startsAt.difference(now) >= refundDeadline;
  }

  static RefundOutcome refundForParticipantCancel({
    required DateTime startsAt,
    required DateTime now,
  }) {
    if (refundsOnParticipantCancel(startsAt: startsAt, now: now)) {
      return const RefundOutcome(
        status: RefundStatus.refunded,
        reason: RefundReason.cancelledInTime,
      );
    }
    return const RefundOutcome(
      status: RefundStatus.denied,
      reason: RefundReason.cancelledTooLate,
    );
  }

  /// The organizer cancelled the event or removed the person. The simulated
  /// payment is returned in full even inside [refundDeadline].
  static RefundOutcome refundForOrganizer(RefundReason reason) {
    return RefundOutcome(status: RefundStatus.refunded, reason: reason);
  }

  /// Half-open intervals: a session that ends at the next session's start
  /// does not overlap it.
  static bool sessionsOverlap({
    required DateTime startA,
    required Duration durationA,
    required DateTime startB,
    required Duration durationB,
  }) {
    final endA = startA.add(durationA);
    final endB = startB.add(durationB);
    return startA.isBefore(endB) && startB.isBefore(endA);
  }

  /// Smallest group size the creator may save.
  ///
  /// It cannot drop below the people already seated, and it cannot drop
  /// below [minGroupSize] while the creator is still looking for someone.
  static int minimumTotalSpots({required int occupiedSpots}) {
    if (occupiedSpots < minGroupSize) {
      return minGroupSize;
    }
    return occupiedSpots;
  }

  static TotalSpotsValidation validateTotalSpots({
    required int totalSpots,
    required int occupiedSpots,
    required int roomCapacity,
  }) {
    if (totalSpots > roomCapacity) {
      return TotalSpotsValidation.exceedsRoomCapacity;
    }
    if (totalSpots < occupiedSpots) {
      return TotalSpotsValidation.belowOccupancy;
    }
    if (totalSpots < minGroupSize) {
      return TotalSpotsValidation.belowMinimum;
    }
    return TotalSpotsValidation.valid;
  }

  static String normalizeNote(String value) => value.trim();

  static bool noteTooLong(String value) =>
      normalizeNote(value).length > maxNoteLength;

  /// Where one membership appears in Meus grupos.
  ///
  /// Upcoming: the person still has a seat, the group is not cancelled,
  /// and the session has not ended (a session in progress stays here).
  /// Past: the session ended and the group was not cancelled.
  /// Cancelled: the organizer deleted the group, or the person left or
  /// was removed. A cancelled group stays here even if the session later
  /// ends.
  static GroupListBucket bucketForMember({
    required bool groupCancelled,
    required bool memberActive,
    required DateTime endsAt,
    required DateTime now,
  }) {
    if (groupCancelled || !memberActive) {
      return GroupListBucket.cancelled;
    }
    if (hasEnded(endsAt: endsAt, now: now)) {
      return GroupListBucket.past;
    }
    return GroupListBucket.upcoming;
  }

  /// Upcoming membership: the group is still on, the person still has a
  /// seat, and the session has not ended.
  static bool isUpcomingForMember({
    required bool groupCancelled,
    required bool memberActive,
    required DateTime endsAt,
    required DateTime now,
  }) {
    return bucketForMember(
          groupCancelled: groupCancelled,
          memberActive: memberActive,
          endsAt: endsAt,
          now: now,
        ) ==
        GroupListBucket.upcoming;
  }
}

enum GroupListBucket { upcoming, past, cancelled }

enum GroupSizeValidation { valid, belowMinimum, exceedsRoomCapacity }

enum TotalSpotsValidation {
  valid,
  belowMinimum,
  belowOccupancy,
  exceedsRoomCapacity,
}
