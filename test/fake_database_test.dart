import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

import 'support/sample_clock.dart';

void main() {
  test('participant ids advance even when no group is created', () {
    final database = loadSampleDatabase();
    final ids = List.generate(4, (_) => database.nextParticipantId());

    expect(ids.toSet(), hasLength(4));
    expect(ids, ['ptc-local-1', 'ptc-local-2', 'ptc-local-3', 'ptc-local-4']);
    expect(database.nextGroupId(), 'grp-local-1');
  });

  test('participant ids skip values already stored on a group', () {
    final database = loadSampleDatabase();
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupSpCoberturaOpen,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(
      participants: [
        ...current.participants,
        const Participant(
          id: 'ptc-local-1',
          displayName: 'Ocupado',
          isCreator: false,
          isLocalUser: false,
        ),
      ],
    );

    expect(database.nextParticipantId(), 'ptc-local-2');
  });

  test('group ids skip values already stored', () {
    final database = loadSampleDatabase();
    database.groups.add(_clone(database.groups.first, id: 'grp-local-1'));

    expect(database.nextGroupId(), 'grp-local-2');
  });
}

Group _clone(Group group, {required String id}) {
  return Group(
    id: id,
    cityId: group.cityId,
    cityName: group.cityName,
    houseId: group.houseId,
    houseName: group.houseName,
    neighborhood: group.neighborhood,
    roomId: group.roomId,
    roomName: group.roomName,
    roomTheme: group.roomTheme,
    roomCapacity: group.roomCapacity,
    durationMinutes: group.durationMinutes,
    difficulty: group.difficulty,
    slotId: group.slotId,
    startsAt: group.startsAt,
    filledSpots: group.filledSpots,
    totalSpots: group.totalSpots,
    priceCents: group.priceCents,
    note: group.note,
    cancelledAt: group.cancelledAt,
    participants: group.participants,
  );
}
