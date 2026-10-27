import 'package:flutter_test/flutter_test.dart';
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
}
