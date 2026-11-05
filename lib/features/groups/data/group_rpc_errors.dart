import 'package:scapematch/features/groups/domain/group_outcomes.dart';

String rpcText({String? code, required String message}) {
  return '${code ?? ''} $message'.toLowerCase();
}

CreateGroupFailureReason createGroupFailure(String text) {
  if (text.contains('conta de recebimento pendente')) {
    return CreateGroupFailureReason.payoutPending;
  }
  if (text.contains('below room minimum')) {
    return CreateGroupFailureReason.belowRoomMinimum;
  }
  if (text.contains('exceeds room capacity')) {
    return CreateGroupFailureReason.exceedsRoomCapacity;
  }
  if (text.contains('session started')) {
    return CreateGroupFailureReason.alreadyStarted;
  }
  if (text.contains('too close')) {
    return CreateGroupFailureReason.tooCloseToStart;
  }
  if (text.contains('overlap')) {
    return CreateGroupFailureReason.overlapsAnotherGroup;
  }
  if (text.contains('duplicate')) {
    return CreateGroupFailureReason.duplicateSession;
  }
  return CreateGroupFailureReason.unknownSelection;
}

JoinFailureReason partyFailure(String text) {
  if (text.contains('party does not fit') || text.contains('group full')) {
    return JoinFailureReason.partyDoesNotFit;
  }
  if (text.contains('not friend') || text.contains('not crew mate')) {
    return JoinFailureReason.companionNotFriend;
  }
  if (text.contains('companion unavailable') ||
      text.contains('invalid companion') ||
      text.contains('party empty') ||
      text.contains('party too large')) {
    return JoinFailureReason.companionUnavailable;
  }
  if (text.contains('blocked')) return JoinFailureReason.blocked;
  return joinFailure(text);
}

CreateGroupFailureReason partyCreateFailure(String text) {
  if (text.contains('open spot required') ||
      text.contains('party does not fit')) {
    return CreateGroupFailureReason.crewLeavesNoOpenSeat;
  }
  if (text.contains('not friend') || text.contains('not crew mate')) {
    return CreateGroupFailureReason.companionNotFriend;
  }
  if (text.contains('companion unavailable') ||
      text.contains('invalid companion') ||
      text.contains('party empty') ||
      text.contains('party too large')) {
    return CreateGroupFailureReason.companionUnavailable;
  }
  return createGroupFailure(text);
}

JoinFailureReason joinFailure(String text) {
  if (text.contains('offer expired') || text.contains('not on waitlist')) {
    return JoinFailureReason.offerExpired;
  }
  if (text.contains('seat reserved')) return JoinFailureReason.seatReserved;
  if (text.contains('already joined')) return JoinFailureReason.alreadyJoined;
  if (text.contains('membership closed')) {
    return JoinFailureReason.membershipClosed;
  }
  if (text.contains('group full')) return JoinFailureReason.full;
  if (text.contains('group cancelled') || text.contains('already cancelled')) {
    return JoinFailureReason.groupCancelled;
  }
  if (text.contains('session ended')) return JoinFailureReason.sessionEnded;
  if (text.contains('session started')) return JoinFailureReason.alreadyStarted;
  if (text.contains('overlap')) return JoinFailureReason.overlapsAnotherGroup;
  if (text.contains('not found') || text.contains('unknown')) {
    return JoinFailureReason.notFound;
  }
  return JoinFailureReason.notFound;
}

LeaveGroupFailureReason leaveFailure(String text) {
  if (text.contains('creator must delete')) {
    return LeaveGroupFailureReason.creatorMustDelete;
  }
  if (text.contains('group cancelled')) {
    return LeaveGroupFailureReason.groupCancelled;
  }
  if (text.contains('session ended')) {
    return LeaveGroupFailureReason.sessionEnded;
  }
  if (text.contains('not member') || text.contains('not found')) {
    return LeaveGroupFailureReason.notMember;
  }
  return LeaveGroupFailureReason.notFound;
}

DeleteGroupFailureReason deleteFailure(String text) {
  if (text.contains('not creator')) return DeleteGroupFailureReason.notCreator;
  if (text.contains('already cancelled')) {
    return DeleteGroupFailureReason.alreadyCancelled;
  }
  if (text.contains('too close')) {
    return DeleteGroupFailureReason.tooCloseToDelete;
  }
  if (text.contains('session ended')) {
    return DeleteGroupFailureReason.sessionEnded;
  }
  if (text.contains('session started')) {
    return DeleteGroupFailureReason.sessionStarted;
  }
  return DeleteGroupFailureReason.notFound;
}

CloseGroupFailureReason closeFailure(String text) {
  if (text.contains('not creator')) return CloseGroupFailureReason.notCreator;
  if (text.contains('already cancelled') || text.contains('group cancelled')) {
    return CloseGroupFailureReason.alreadyCancelled;
  }
  if (text.contains('session started')) {
    return CloseGroupFailureReason.sessionStarted;
  }
  if (text.contains('below room minimum')) {
    return CloseGroupFailureReason.belowRoomMinimum;
  }
  if (text.contains('already planned')) {
    return CloseGroupFailureReason.alreadyPlannedSize;
  }
  return CloseGroupFailureReason.notFound;
}

RemoveMemberFailureReason removeFailure(String text) {
  if (text.contains('cannot remove creator')) {
    return RemoveMemberFailureReason.cannotRemoveCreator;
  }
  if (text.contains('not creator')) return RemoveMemberFailureReason.notCreator;
  if (text.contains('member not found')) {
    return RemoveMemberFailureReason.memberNotFound;
  }
  if (text.contains('group cancelled')) {
    return RemoveMemberFailureReason.groupCancelled;
  }
  if (text.contains('session ended')) {
    return RemoveMemberFailureReason.sessionEnded;
  }
  if (text.contains('session started')) {
    return RemoveMemberFailureReason.sessionStarted;
  }
  return RemoveMemberFailureReason.notFound;
}

EditGroupFailureReason editFailure(String text) {
  if (text.contains('not creator')) return EditGroupFailureReason.notCreator;
  if (text.contains('below occupancy')) {
    return EditGroupFailureReason.belowOccupancy;
  }
  if (text.contains('below room minimum')) {
    return EditGroupFailureReason.belowRoomMinimum;
  }
  if (text.contains('below minimum')) {
    return EditGroupFailureReason.belowMinimum;
  }
  if (text.contains('exceeds room capacity')) {
    return EditGroupFailureReason.exceedsRoomCapacity;
  }
  if (text.contains('note too long')) return EditGroupFailureReason.noteTooLong;
  if (text.contains('group cancelled')) {
    return EditGroupFailureReason.groupCancelled;
  }
  if (text.contains('session ended')) {
    return EditGroupFailureReason.sessionEnded;
  }
  return EditGroupFailureReason.notFound;
}

ConfirmAttendanceFailureReason confirmFailure(String text) {
  if (text.contains('not member')) {
    return ConfirmAttendanceFailureReason.notMember;
  }
  if (text.contains('group cancelled')) {
    return ConfirmAttendanceFailureReason.groupCancelled;
  }
  if (text.contains('session ended')) {
    return ConfirmAttendanceFailureReason.sessionEnded;
  }
  return ConfirmAttendanceFailureReason.notFound;
}

String waitlistError(String text) {
  if (text.contains('already joined')) return 'Você já está neste grupo.';
  if (text.contains('display name')) {
    return 'Sua conta ainda não tem nome. Entre de novo.';
  }
  if (text.contains('not found')) return 'Não encontramos esse grupo.';
  if (text.contains('not authenticated')) return 'Entre para entrar na fila.';
  return 'Não foi possível entrar na fila.';
}
