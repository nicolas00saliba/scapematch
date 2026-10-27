import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Sample implementation of [GroupRepository].
///
/// [failList] exists so the error screen can be tested. The real app leaves
/// it false. Changes live only inside [FakeDatabase]. Time comes from [clock].
class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(
    this._database, {
    this.clock = const SystemClock(),
    this.latency = const Duration(milliseconds: 280),
    this.failList = false,
  });

  final FakeDatabase _database;
  final Clock clock;
  final Duration latency;
  final bool failList;

  @override
  Future<List<Group>> listByCity(
    String cityId, {
    bool almostFullOnly = false,
  }) async {
    await _pause();
    if (failList) {
      throw Exception('sample list failed');
    }
    final now = clock.now();
    final groups = _database.groups.where((group) {
      if (group.cityId != cityId || !_listed(group, now)) {
        return false;
      }
      if (almostFullOnly && !group.isAlmostFull) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(groups);
  }

  @override
  Future<List<Group>> listForUser(String userId) async {
    await _pause();
    final groups =
        _database.groups
            .where((group) => group.participantForUser(userId) != null)
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(groups);
  }

  @override
  Future<Group?> getById(String id) async {
    await _pause();
    return _find(id);
  }

  @override
  Future<JoinResult> join(
    String groupId, {
    required String participantUserId,
    required String participantName,
    bool markAsLocalUser = true,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const JoinFailure(JoinFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (current.isCancelled) {
      return const JoinFailure(JoinFailureReason.groupCancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.sessionEnded);
    }
    final mine = current.participantForUser(participantUserId);
    if (mine != null && mine.occupiesSeat) {
      return const JoinFailure(JoinFailureReason.alreadyJoined);
    }
    if (mine != null) {
      return const JoinFailure(JoinFailureReason.membershipClosed);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.alreadyStarted);
    }
    if (_overlaps(
      userId: participantUserId,
      startsAt: current.startsAt,
      durationMinutes: current.durationMinutes,
      ignoringGroupId: current.id,
    )) {
      return const JoinFailure(JoinFailureReason.overlapsAnotherGroup);
    }
    if (!GroupRules.canJoin(
      filledSpots: current.filledSpots,
      totalSpots: current.totalSpots,
    )) {
      return const JoinFailure(JoinFailureReason.full);
    }
    final updated = current.copyWith(
      filledSpots: current.filledSpots + 1,
      participants: [
        ...current.participants,
        Participant(
          id: _database.nextParticipantId(),
          userId: participantUserId,
          displayName: participantName,
          isCreator: false,
          isLocalUser: markAsLocalUser,
        ),
      ],
    );
    _database.groups[index] = updated;
    return JoinSuccess(updated);
  }

  @override
  Future<CreateGroupResult> create(CreateGroupRequest request) async {
    await _pause();
    final city = _database.cityById(request.cityId);
    final house = _database.houseById(request.houseId);
    final room = _database.roomById(request.roomId);
    final slot = _database.slotById(request.slotId);
    if (city == null ||
        house == null ||
        room == null ||
        slot == null ||
        house.cityId != city.id ||
        room.houseId != house.id ||
        slot.roomId != room.id) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.unknownSelection,
      );
    }

    final validation = GroupRules.validateGroupSize(
      extraSpots: request.extraSpots,
      roomCapacity: room.capacity,
    );
    switch (validation) {
      case GroupSizeValidation.belowMinimum:
        return const CreateGroupFailure(CreateGroupFailureReason.belowMinimum);
      case GroupSizeValidation.exceedsRoomCapacity:
        return const CreateGroupFailure(
          CreateGroupFailureReason.exceedsRoomCapacity,
        );
      case GroupSizeValidation.valid:
        break;
    }

    final now = clock.now();
    if (GroupRules.hasStarted(startsAt: slot.startsAt, now: now)) {
      return const CreateGroupFailure(CreateGroupFailureReason.alreadyStarted);
    }

    final taken = GroupRules.roomAndTimeTaken(
      roomId: room.id,
      startsAt: slot.startsAt,
      existing: [
        for (final group in _database.groups)
          if (!group.isCancelled)
            (roomId: group.roomId, startsAt: group.startsAt),
      ],
    );
    if (taken) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.duplicateSession,
      );
    }

    if (_overlaps(
      userId: request.creatorUserId,
      startsAt: slot.startsAt,
      durationMinutes: room.durationMinutes,
    )) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.overlapsAnotherGroup,
      );
    }

    final id = _database.nextGroupId();
    final group = Group(
      id: id,
      cityId: city.id,
      cityName: city.name,
      houseId: house.id,
      houseName: house.name,
      neighborhood: house.neighborhood,
      roomId: room.id,
      roomName: room.name,
      roomTheme: room.theme,
      roomCapacity: room.capacity,
      durationMinutes: room.durationMinutes,
      difficulty: room.difficulty,
      slotId: slot.id,
      startsAt: slot.startsAt,
      filledSpots: 1,
      totalSpots: 1 + request.extraSpots,
      priceCents: room.priceCents,
      participants: [
        Participant(
          id: _database.nextParticipantId(),
          userId: request.creatorUserId,
          displayName: request.creatorDisplayName,
          isCreator: true,
          isLocalUser: true,
        ),
      ],
    );
    _database.groups.add(group);
    return CreateGroupSuccess(group);
  }

  @override
  Future<ConfirmAttendanceResult> confirmAttendance(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    switch (_lookupSeat(groupId, userId)) {
      case _SeatProblem(:final kind):
        return ConfirmAttendanceFailure(_confirmProblem(kind));
      case _SeatFound(:final index, :final group, :final member):
        final updated = _replaceMember(
          group,
          member.copyWith(attendance: AttendanceStatus.confirmed),
        );
        _database.groups[index] = updated;
        return ConfirmAttendanceSuccess(updated);
    }
  }

  @override
  Future<LeaveGroupResult> leave(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    switch (_lookupSeat(groupId, userId)) {
      case _SeatProblem(:final kind):
        return LeaveGroupFailure(_leaveProblem(kind));
      case _SeatFound(
        index: final index,
        group: final current,
        member: final member,
      ):
        if (member.isCreator) {
          return const LeaveGroupFailure(
            LeaveGroupFailureReason.creatorMustDelete,
          );
        }
        final outcome = GroupRules.refundForParticipantCancel(
          startsAt: current.startsAt,
          now: clock.now(),
        );
        final updatedPeople = [
          for (final person in current.participants)
            if (person.id == member.id)
              person.copyWith(
                attendance: AttendanceStatus.cancelled,
                refund: outcome.status,
                refundReason: outcome.reason,
              )
            else
              person,
        ];
        final updated = current.copyWith(
          participants: updatedPeople,
          filledSpots: _occupied(updatedPeople),
        );
        _database.groups[index] = updated;
        return LeaveGroupSuccess(updated);
    }
  }

  @override
  Future<DeleteGroupResult> deleteGroup(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.notFound);
    }
    final current = _database.groups[index];
    if (!current.createdBy(userId)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const DeleteGroupFailure(
        DeleteGroupFailureReason.alreadyCancelled,
      );
    }
    final now = clock.now();
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.sessionEnded);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.sessionStarted);
    }
    final outcome = GroupRules.refundForOrganizer(
      RefundReason.organizerCancelledEvent,
    );
    final updated = current.copyWith(
      cancelledAt: now,
      filledSpots: 0,
      participants: [
        for (final person in current.participants)
          if (person.occupiesSeat)
            person.copyWith(
              attendance: AttendanceStatus.cancelled,
              refund: outcome.status,
              refundReason: outcome.reason,
            )
          else
            person,
      ],
    );
    _database.groups[index] = updated;
    return DeleteGroupSuccess(updated);
  }

  @override
  Future<RemoveMemberResult> removeMember(
    String groupId, {
    required String actorUserId,
    required String memberId,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (!current.createdBy(actorUserId)) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.groupCancelled,
      );
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.sessionEnded);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.sessionStarted,
      );
    }
    Participant? target;
    for (final person in current.participants) {
      if (person.id == memberId) {
        target = person;
        break;
      }
    }
    if (target == null || !target.occupiesSeat) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.memberNotFound,
      );
    }
    if (target.isCreator) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.cannotRemoveCreator,
      );
    }
    final outcome = GroupRules.refundForOrganizer(
      RefundReason.organizerRemovedMember,
    );
    final updatedPeople = [
      for (final person in current.participants)
        if (person.id == target.id)
          person.copyWith(
            attendance: AttendanceStatus.cancelled,
            refund: outcome.status,
            refundReason: outcome.reason,
          )
        else
          person,
    ];
    final updated = current.copyWith(
      participants: updatedPeople,
      filledSpots: _occupied(updatedPeople),
    );
    _database.groups[index] = updated;
    return RemoveMemberSuccess(updated);
  }

  @override
  Future<EditGroupResult> edit(
    String groupId, {
    required String actorUserId,
    required int totalSpots,
    required String note,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const EditGroupFailure(EditGroupFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (!current.createdBy(actorUserId)) {
      return const EditGroupFailure(EditGroupFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const EditGroupFailure(EditGroupFailureReason.groupCancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const EditGroupFailure(EditGroupFailureReason.sessionEnded);
    }
    if (GroupRules.noteTooLong(note)) {
      return const EditGroupFailure(EditGroupFailureReason.noteTooLong);
    }
    final occupied = current.occupiedSpots;
    final validation = GroupRules.validateTotalSpots(
      totalSpots: totalSpots,
      occupiedSpots: occupied,
      roomCapacity: current.roomCapacity,
    );
    switch (validation) {
      case TotalSpotsValidation.belowMinimum:
        return const EditGroupFailure(EditGroupFailureReason.belowMinimum);
      case TotalSpotsValidation.belowOccupancy:
        return const EditGroupFailure(EditGroupFailureReason.belowOccupancy);
      case TotalSpotsValidation.exceedsRoomCapacity:
        return const EditGroupFailure(
          EditGroupFailureReason.exceedsRoomCapacity,
        );
      case TotalSpotsValidation.valid:
        break;
    }
    final updated = current.copyWith(
      totalSpots: totalSpots,
      note: GroupRules.normalizeNote(note),
    );
    _database.groups[index] = updated;
    return EditGroupSuccess(updated);
  }

  bool _listed(Group group, DateTime now) {
    if (group.isCancelled) {
      return false;
    }
    return !GroupRules.hasEnded(endsAt: group.endsAt, now: now);
  }

  bool _overlaps({
    required String userId,
    required DateTime startsAt,
    required int durationMinutes,
    String? ignoringGroupId,
  }) {
    final now = clock.now();
    final window = Duration(minutes: durationMinutes);
    for (final group in _database.groups) {
      if (group.id == ignoringGroupId || group.isCancelled) {
        continue;
      }
      if (GroupRules.hasEnded(endsAt: group.endsAt, now: now)) {
        continue;
      }
      final member = group.participantForUser(userId);
      if (member == null || !member.occupiesSeat) {
        continue;
      }
      if (GroupRules.sessionsOverlap(
        startA: group.startsAt,
        durationA: Duration(minutes: group.durationMinutes),
        startB: startsAt,
        durationB: window,
      )) {
        return true;
      }
    }
    return false;
  }

  _SeatLookup _lookupSeat(String groupId, String userId) {
    final index = _indexOf(groupId);
    if (index < 0) {
      return const _SeatProblem(_SeatKind.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (current.isCancelled) {
      return const _SeatProblem(_SeatKind.cancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const _SeatProblem(_SeatKind.ended);
    }
    final member = current.participantForUser(userId);
    if (member == null || !member.occupiesSeat) {
      return const _SeatProblem(_SeatKind.notMember);
    }
    return _SeatFound(index, current, member);
  }

  ConfirmAttendanceFailureReason _confirmProblem(_SeatKind kind) {
    return switch (kind) {
      _SeatKind.notFound => ConfirmAttendanceFailureReason.notFound,
      _SeatKind.cancelled => ConfirmAttendanceFailureReason.groupCancelled,
      _SeatKind.ended => ConfirmAttendanceFailureReason.sessionEnded,
      _SeatKind.notMember => ConfirmAttendanceFailureReason.notMember,
    };
  }

  LeaveGroupFailureReason _leaveProblem(_SeatKind kind) {
    return switch (kind) {
      _SeatKind.notFound => LeaveGroupFailureReason.notFound,
      _SeatKind.cancelled => LeaveGroupFailureReason.groupCancelled,
      _SeatKind.ended => LeaveGroupFailureReason.sessionEnded,
      _SeatKind.notMember => LeaveGroupFailureReason.notMember,
    };
  }

  Group _replaceMember(Group group, Participant member) {
    return group.copyWith(
      participants: [
        for (final person in group.participants)
          if (person.id == member.id) member else person,
      ],
    );
  }

  int _occupied(List<Participant> people) {
    return people.where((person) => person.occupiesSeat).length;
  }

  Group? _find(String id) {
    final index = _indexOf(id);
    if (index < 0) {
      return null;
    }
    return _database.groups[index];
  }

  int _indexOf(String id) {
    return _database.groups.indexWhere((group) => group.id == id);
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}

enum _SeatKind { notFound, cancelled, ended, notMember }

sealed class _SeatLookup {
  const _SeatLookup();
}

class _SeatProblem extends _SeatLookup {
  const _SeatProblem(this.kind);

  final _SeatKind kind;
}

class _SeatFound extends _SeatLookup {
  const _SeatFound(this.index, this.group, this.member);

  final int index;
  final Group group;
  final Participant member;
}
