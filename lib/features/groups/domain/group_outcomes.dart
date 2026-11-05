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
  const JoinFailure(this.reason, {this.detail});

  final JoinFailureReason reason;

  /// Texto pronto, quando a falha nomeia quem impediu a turma de entrar.
  final String? detail;
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

  /// A turma inteira não cabe. Nenhuma cadeira foi ocupada.
  partyDoesNotFit,

  /// Alguém da turma não é amigo aceito de quem está entrando.
  companionNotFriend,

  /// Alguém da turma não pode sentar (horário, bloqueio ou cadeira antiga).
  companionUnavailable,
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
  tooCloseToStart,
  overlapsAnotherGroup,

  /// A turma preencheria o grupo inteiro e não sobraria vaga aberta.
  crewLeavesNoOpenSeat,
  companionNotFriend,
  companionUnavailable,

  /// A casa aprovada ainda não tem conta de recebimento.
  payoutPending,
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

sealed class CloseGroupResult {
  const CloseGroupResult();
}

final class CloseGroupSuccess extends CloseGroupResult {
  const CloseGroupSuccess(this.group);

  final Group group;
}

final class CloseGroupFailure extends CloseGroupResult {
  const CloseGroupFailure(this.reason);

  final CloseGroupFailureReason reason;
}

enum CloseGroupFailureReason {
  notFound,
  notCreator,
  alreadyCancelled,
  sessionStarted,
  belowRoomMinimum,
  alreadyPlannedSize,
}

enum DeleteGroupFailureReason {
  notFound,
  notCreator,
  alreadyCancelled,
  sessionStarted,
  sessionEnded,
  tooCloseToDelete,
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

sealed class PayShareResult {
  const PayShareResult();
}

final class PayShareSuccess extends PayShareResult {
  const PayShareSuccess(this.group);

  final Group group;
}

final class PayShareFailure extends PayShareResult {
  const PayShareFailure(this.reason);

  final PayShareFailureReason reason;
}

enum PayShareFailureReason {
  notFound,
  notSeated,
  alreadyPaid,
  groupCancelled,
  unavailable,
}

class GroupNotFoundException implements Exception {
  GroupNotFoundException(this.groupId);

  final String groupId;

  @override
  String toString() => 'Group not found: $groupId';
}
