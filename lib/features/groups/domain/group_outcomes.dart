import 'package:scapematch/features/groups/domain/group.dart';

/// Results of "enter group" and "create group".
///
/// They are plain values, not exceptions, because a full group or a group
/// that does not fit the room is a normal answer — not a crash.
sealed class JoinResult {
  const JoinResult();
}

final class JoinSuccess extends JoinResult {
  const JoinSuccess(this.group);

  final Group group;
}

final class JoinFailure extends JoinResult {
  const JoinFailure(this.reason);

  final JoinFailureReason reason;
}

enum JoinFailureReason { notFound, full, alreadyJoined }

sealed class CreateGroupResult {
  const CreateGroupResult();
}

final class CreateGroupSuccess extends CreateGroupResult {
  const CreateGroupSuccess(this.group);

  final Group group;
}

final class CreateGroupFailure extends CreateGroupResult {
  const CreateGroupFailure(this.reason);

  final CreateGroupFailureReason reason;
}

enum CreateGroupFailureReason {
  unknownSelection,
  belowMinimum,
  exceedsRoomCapacity,
}

class GroupNotFoundException implements Exception {
  GroupNotFoundException(this.groupId);

  final String groupId;

  @override
  String toString() => 'Group not found: $groupId';
}
