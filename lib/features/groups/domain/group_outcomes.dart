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

enum JoinFailureReason {
  notFound,
  full,
  alreadyJoined,
  alreadyStarted,
  overlapsAnotherGroup,
  membershipClosed,
  groupCancelled,
  sessionEnded,
  blocked,
  restricted,
  seatReserved,
  offerExpired,
}

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
  belowRoomMinimum,
  exceedsRoomCapacity,

  /// Another group already occupies this room at this start time.
  duplicateSession,
  alreadyStarted,
  overlapsAnotherGroup,
}

sealed class ConfirmAttendanceResult {
  const ConfirmAttendanceResult();
}

final class ConfirmAttendanceSuccess extends ConfirmAttendanceResult {
  const ConfirmAttendanceSuccess(this.group);

  final Group group;
}

final class ConfirmAttendanceFailure extends ConfirmAttendanceResult {
  const ConfirmAttendanceFailure(this.reason);

  final ConfirmAttendanceFailureReason reason;
}

enum ConfirmAttendanceFailureReason {
  notFound,
  notMember,
  groupCancelled,
  sessionEnded,
}

sealed class LeaveGroupResult {
  const LeaveGroupResult();
}

final class LeaveGroupSuccess extends LeaveGroupResult {
  const LeaveGroupSuccess(this.group);

  final Group group;
}

final class LeaveGroupFailure extends LeaveGroupResult {
  const LeaveGroupFailure(this.reason);

  final LeaveGroupFailureReason reason;
}

enum LeaveGroupFailureReason {
  notFound,
  notMember,
  creatorMustDelete,
  groupCancelled,
  sessionEnded,
}

sealed class DeleteGroupResult {
  const DeleteGroupResult();
}

final class DeleteGroupSuccess extends DeleteGroupResult {
  const DeleteGroupSuccess(this.group);

  final Group group;
}

final class DeleteGroupFailure extends DeleteGroupResult {
  const DeleteGroupFailure(this.reason);

  final DeleteGroupFailureReason reason;
}

enum DeleteGroupFailureReason {
  notFound,
  notCreator,
  alreadyCancelled,
  sessionStarted,
  sessionEnded,
}

sealed class RemoveMemberResult {
  const RemoveMemberResult();
}

final class RemoveMemberSuccess extends RemoveMemberResult {
  const RemoveMemberSuccess(this.group);

  final Group group;
}

final class RemoveMemberFailure extends RemoveMemberResult {
  const RemoveMemberFailure(this.reason);

  final RemoveMemberFailureReason reason;
}

enum RemoveMemberFailureReason {
  notFound,
  notCreator,
  memberNotFound,
  cannotRemoveCreator,
  groupCancelled,
  sessionStarted,
  sessionEnded,
}

sealed class EditGroupResult {
  const EditGroupResult();
}

final class EditGroupSuccess extends EditGroupResult {
  const EditGroupSuccess(this.group);

  final Group group;
}

final class EditGroupFailure extends EditGroupResult {
  const EditGroupFailure(this.reason);

  final EditGroupFailureReason reason;
}

enum EditGroupFailureReason {
  notFound,
  notCreator,
  belowOccupancy,
  belowMinimum,
  belowRoomMinimum,
  exceedsRoomCapacity,
  noteTooLong,
  groupCancelled,
  sessionEnded,
}

class GroupNotFoundException implements Exception {
  GroupNotFoundException(this.groupId);

  final String groupId;

  @override
  String toString() => 'Group not found: $groupId';
}
