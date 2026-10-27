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
  });
}
