import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

void main() {
  group('joining a group', () {
    test('rejects a group that has no open seats', () {
      expect(GroupRules.canJoin(filledSpots: 4, totalSpots: 4), isFalse);
      expect(GroupRules.canJoin(filledSpots: 6, totalSpots: 6), isFalse);
    });

    test('allows a group that still has room', () {
      expect(GroupRules.canJoin(filledSpots: 5, totalSpots: 6), isTrue);
      expect(GroupRules.canJoin(filledSpots: 1, totalSpots: 4), isTrue);
    });
  });

  group('Quase cheios filter', () {
    test('keeps groups missing one or two seats', () {
      expect(GroupRules.isAlmostFull(filledSpots: 4, totalSpots: 5), isTrue);
      expect(GroupRules.isAlmostFull(filledSpots: 4, totalSpots: 6), isTrue);
    });

    test('drops full groups and groups with many open seats', () {
      expect(GroupRules.isAlmostFull(filledSpots: 6, totalSpots: 6), isFalse);
      expect(GroupRules.isAlmostFull(filledSpots: 1, totalSpots: 6), isFalse);
      expect(GroupRules.isAlmostFull(filledSpots: 2, totalSpots: 6), isFalse);
    });

    test('the open-seat limit is the GroupRules constant', () {
      expect(GroupRules.almostFullMaxOpenSeats, 2);
      expect(
        GroupRules.isAlmostFull(
          filledSpots: 4,
          totalSpots: 4 + GroupRules.almostFullMaxOpenSeats,
        ),
        isTrue,
      );
      expect(
        GroupRules.isAlmostFull(
          filledSpots: 4,
          totalSpots: 4 + GroupRules.almostFullMaxOpenSeats + 1,
        ),
        isFalse,
      );
    });
  });

  group('creating a group', () {
    test('accepts a size that fits the room, counting the creator', () {
      expect(
        GroupRules.validateGroupSize(extraSpots: 3, roomCapacity: 4),
        GroupSizeValidation.valid,
      );
      expect(
        GroupRules.validateGroupSize(extraSpots: 5, roomCapacity: 6),
        GroupSizeValidation.valid,
      );
    });

    test('rejects a size above the room capacity', () {
      expect(
        GroupRules.validateGroupSize(extraSpots: 4, roomCapacity: 4),
        GroupSizeValidation.exceedsRoomCapacity,
      );
      expect(
        GroupRules.validateGroupSize(extraSpots: 8, roomCapacity: 6),
        GroupSizeValidation.exceedsRoomCapacity,
      );
    });

    test('rejects a group with nobody besides the creator', () {
      expect(
        GroupRules.validateGroupSize(extraSpots: 0, roomCapacity: 6),
        GroupSizeValidation.belowMinimum,
      );
    });

    test('the extra-seat ceiling is the room, not a fixed 12', () {
      expect(GroupRules.minExtraSpots, 1);
      expect(GroupRules.maxExtraSpots(roomCapacity: null), isNull);
      expect(GroupRules.maxExtraSpots(roomCapacity: 6), 5);
      expect(GroupRules.clampExtraSpots(0), 1);
      expect(GroupRules.clampExtraSpots(20), 20);
      expect(GroupRules.clampExtraSpots(12, roomCapacity: 6), 5);
      expect(GroupRules.clampExtraSpots(3, roomCapacity: 8), 3);
    });
  });

  group('one group per room and time', () {
    final at = DateTime(2026, 11, 8, 16);

    test('rejects the same room at the same start', () {
      expect(
        GroupRules.roomAndTimeTaken(
          roomId: 'room-a',
          startsAt: at,
          existing: [(roomId: 'room-a', startsAt: at)],
        ),
        isTrue,
      );
    });

    test('allows the same room at another time', () {
      expect(
        GroupRules.roomAndTimeTaken(
          roomId: 'room-a',
          startsAt: at,
          existing: [
            (roomId: 'room-a', startsAt: at.add(const Duration(hours: 2))),
          ],
        ),
        isFalse,
      );
    });

    test('allows another room at the same time', () {
      expect(
        GroupRules.roomAndTimeTaken(
          roomId: 'room-b',
          startsAt: at,
          existing: [(roomId: 'room-a', startsAt: at)],
        ),
        isFalse,
      );
    });
  });

  group('refund window', () {
    final now = DateTime(2026, 10, 27, 12);

    test('refunds exactly two hours before the start', () {
      expect(GroupRules.refundDeadline, const Duration(hours: 2));
      final startsAt = now.add(GroupRules.refundDeadline);
      expect(
        GroupRules.refundsOnParticipantCancel(startsAt: startsAt, now: now),
        isTrue,
      );
      final outcome = GroupRules.refundForParticipantCancel(
        startsAt: startsAt,
        now: now,
      );
      expect(outcome.status, RefundStatus.refunded);
      expect(outcome.reason, RefundReason.cancelledInTime);
    });

    test(
      'refunds one minute outside the window and refuses one minute inside',
      () {
        final outside = now
            .add(GroupRules.refundDeadline)
            .add(const Duration(minutes: 1));
        final inside = now
            .add(GroupRules.refundDeadline)
            .subtract(const Duration(minutes: 1));
        expect(
          GroupRules.refundsOnParticipantCancel(startsAt: outside, now: now),
          isTrue,
        );
        expect(
          GroupRules.refundsOnParticipantCancel(startsAt: inside, now: now),
          isFalse,
        );
        expect(
          GroupRules.refundForParticipantCancel(
            startsAt: inside,
            now: now,
          ).reason,
          RefundReason.cancelledTooLate,
        );
      },
    );

    test('a session that starts in under two hours does not refund', () {
      final startsAt = now.add(const Duration(minutes: 90));
      expect(
        GroupRules.refundsOnParticipantCancel(startsAt: startsAt, now: now),
        isFalse,
      );
    });

    test('the organizer refunds even inside the window', () {
      final startsAt = now.add(const Duration(minutes: 30));
      expect(
        GroupRules.refundsOnParticipantCancel(startsAt: startsAt, now: now),
        isFalse,
      );
      final outcome = GroupRules.refundForOrganizer(
        RefundReason.organizerCancelledEvent,
      );
      expect(outcome.status, RefundStatus.refunded);
      expect(outcome.reason, RefundReason.organizerCancelledEvent);
    });
  });

  group('schedule conflicts', () {
    final start = DateTime(2026, 10, 27, 16);

    test('overlapping sessions block each other', () {
      expect(
        GroupRules.sessionsOverlap(
          startA: start,
          durationA: const Duration(minutes: 75),
          startB: start.add(const Duration(minutes: 30)),
          durationB: const Duration(minutes: 60),
        ),
        isTrue,
      );
    });

    test('a session that starts when the other ends does not overlap', () {
      expect(
        GroupRules.sessionsOverlap(
          startA: start,
          durationA: const Duration(hours: 1),
          startB: start.add(const Duration(hours: 1)),
          durationB: const Duration(hours: 1),
        ),
        isFalse,
      );
    });

    test('a session has started at the exact start instant', () {
      expect(GroupRules.hasStarted(startsAt: start, now: start), isTrue);
      expect(
        GroupRules.hasStarted(
          startsAt: start,
          now: start.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('a session has ended at the exact end instant', () {
      final endsAt = start.add(const Duration(minutes: 60));
      expect(GroupRules.hasEnded(endsAt: endsAt, now: endsAt), isTrue);
      expect(
        GroupRules.hasEnded(
          endsAt: endsAt,
          now: endsAt.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });
  });

  group('editing the group size', () {
    test('rejects a size below who already joined', () {
      expect(
        GroupRules.validateTotalSpots(
          totalSpots: 4,
          occupiedSpots: 5,
          roomCapacity: 6,
        ),
        TotalSpotsValidation.belowOccupancy,
      );
    });

    test('rejects a size above the room and a group of one', () {
      expect(
        GroupRules.validateTotalSpots(
          totalSpots: 7,
          occupiedSpots: 2,
          roomCapacity: 6,
        ),
        TotalSpotsValidation.exceedsRoomCapacity,
      );
      expect(
        GroupRules.validateTotalSpots(
          totalSpots: 1,
          occupiedSpots: 1,
          roomCapacity: 6,
        ),
        TotalSpotsValidation.belowMinimum,
      );
    });

    test('the floor is who already joined once that passes two', () {
      expect(GroupRules.minimumTotalSpots(occupiedSpots: 1), 2);
      expect(GroupRules.minimumTotalSpots(occupiedSpots: 5), 5);
    });
  });

  group('my groups buckets', () {
    final now = DateTime(2026, 10, 27, 12);
    final endsAt = now.add(const Duration(hours: 3));

    test('an active future seat stays upcoming', () {
      expect(
        GroupRules.isUpcomingForMember(
          groupCancelled: false,
          memberActive: true,
          endsAt: endsAt,
          now: now,
        ),
        isTrue,
      );
    });

    test(
      'a cancelled group, a left seat, or a finished session is history',
      () {
        expect(
          GroupRules.isUpcomingForMember(
            groupCancelled: true,
            memberActive: true,
            endsAt: endsAt,
            now: now,
          ),
          isFalse,
        );
        expect(
          GroupRules.isUpcomingForMember(
            groupCancelled: false,
            memberActive: false,
            endsAt: endsAt,
            now: now,
          ),
          isFalse,
        );
        expect(
          GroupRules.isUpcomingForMember(
            groupCancelled: false,
            memberActive: true,
            endsAt: now,
            now: now,
          ),
          isFalse,
        );
      },
    );
  });
}
