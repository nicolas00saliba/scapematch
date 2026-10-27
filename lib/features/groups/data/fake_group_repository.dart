import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Sample implementation of [GroupRepository].
///
/// [failList] exists so the error screen can be tested. The real app leaves
/// it false. Changes live only inside [FakeDatabase].
class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(
    this._database, {
    this.latency = const Duration(milliseconds: 280),
    this.failList = false,
  });

  final FakeDatabase _database;
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
    final groups = _database.groups.where((group) {
      if (group.cityId != cityId) {
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
  Future<Group?> getById(String id) async {
    await _pause();
    for (final group in _database.groups) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  @override
  Future<JoinResult> join(
    String groupId, {
    required String participantName,
  }) async {
    await _pause();
    final index = _database.groups.indexWhere((group) => group.id == groupId);
    if (index < 0) {
      return const JoinFailure(JoinFailureReason.notFound);
    }
    final current = _database.groups[index];
    // Already inside wins over "full", so a second tap explains itself.
    if (current.joinedByMe) {
      return const JoinFailure(JoinFailureReason.alreadyJoined);
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
          id: _database.nextParticipantId(groupId),
          displayName: participantName,
          isCreator: false,
          isLocalUser: true,
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
      participants: [
        Participant(
          id: _database.nextParticipantId(id),
          displayName: 'Você',
          isCreator: true,
          isLocalUser: true,
        ),
      ],
    );
    _database.groups.add(group);
    return CreateGroupSuccess(group);
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
