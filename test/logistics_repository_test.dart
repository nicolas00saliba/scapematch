import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

import 'support/sample_clock.dart';

void main() {
  late FakeDatabase database;
  late FakeGroupRepository groups;
  late FixedClock clock;

  setUp(() {
    clock = loadSampleClock();
    database = loadSampleDatabase();
    groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
  });

  test(
    'each city has one session inside the refund window and one outside',
    () {
      for (final cityId in SampleIds.cities) {
        final cityGroups = database.groups.where(
          (group) => group.cityId == cityId,
        );
        expect(cityGroups, hasLength(2), reason: cityId);
        final soon = cityGroups.where(
          (group) =>
              group.startsAt.isAfter(sampleNow) &&
              group.startsAt.difference(sampleNow) < GroupRules.refundDeadline,
        );
        final later = cityGroups.where(
          (group) =>
              group.startsAt.difference(sampleNow) >= GroupRules.refundDeadline,
        );
        expect(soon, hasLength(1), reason: cityId);
        expect(soon.single.isAlmostFull, isTrue, reason: cityId);
        expect(later, hasLength(1), reason: cityId);
        expect(
          GroupRules.sessionsOverlap(
            startA: soon.single.startsAt,
            durationA: Duration(minutes: soon.single.durationMinutes),
            startB: later.single.startsAt,
            durationB: Duration(minutes: later.single.durationMinutes),
          ),
          isFalse,
          reason: cityId,
        );
      }
    },
  );

  test('joining inside the window and then leaving does not refund', () async {
    final before = await groups.getById(SampleIds.groupSpMetroAlmost);
    expect(
      before!.startsAt.difference(sampleNow) < GroupRules.refundDeadline,
      isTrue,
    );

    final joined = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(joined, isA<JoinSuccess>());
    expect((joined as JoinSuccess).group.filledSpots, before.filledSpots + 1);

    final left = await groups.leave(
      SampleIds.groupSpMetroAlmost,
      userId: 'user-local',
    );
    expect(left, isA<LeaveGroupSuccess>());
    final group = (left as LeaveGroupSuccess).group;
    final me = group.participantForUser('user-local')!;
    expect(me.attendance, AttendanceStatus.cancelled);
    expect(me.refund, RefundStatus.denied);
    expect(me.refundReason, RefundReason.cancelledTooLate);
    expect(group.filledSpots, before.filledSpots);

    final again = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(again, isA<JoinFailure>());
    expect((again as JoinFailure).reason, JoinFailureReason.membershipClosed);

    final takenBySomeoneElse = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-other',
      participantName: 'Outra',
      markAsLocalUser: false,
    );
    expect(takenBySomeoneElse, isA<JoinSuccess>());
    expect(
      (takenBySomeoneElse as JoinSuccess).group.filledSpots,
      before.filledSpots + 1,
    );
  });

  test('leaving at least two hours ahead refunds and frees the seat', () async {
    final before = await groups.getById(SampleIds.groupSpCoberturaOpen);
    final joined = await groups.join(
      SampleIds.groupSpCoberturaOpen,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(joined, isA<JoinSuccess>());

    final left = await groups.leave(
      SampleIds.groupSpCoberturaOpen,
      userId: 'user-local',
    );
    final group = (left as LeaveGroupSuccess).group;
    final me = group.participantForUser('user-local')!;
    expect(me.refund, RefundStatus.refunded);
    expect(me.refundReason, RefundReason.cancelledInTime);
    expect(group.filledSpots, before!.filledSpots);
    expect(group.openSeats, before.openSeats);
  });

  test('exactly two hours refunds and one minute less does not', () async {
    await _expectRefund(
      groups,
      database,
      sampleNow.add(const Duration(hours: 2)),
      RefundStatus.refunded,
      RefundReason.cancelledInTime,
    );
    await _expectRefund(
      groups,
      database,
      sampleNow.add(const Duration(hours: 2, minutes: 1)),
      RefundStatus.refunded,
      RefundReason.cancelledInTime,
    );
    await _expectRefund(
      groups,
      database,
      sampleNow.add(const Duration(hours: 1, minutes: 59)),
      RefundStatus.denied,
      RefundReason.cancelledTooLate,
    );
  });

  test(
    'the creator cannot leave and deletes with a full refund inside the window',
    () async {
      final created = await groups.create(
        _request(
          extraSpots: 2,
          creatorUserId: 'user-ana',
          creatorDisplayName: 'Ana',
        ),
      );
      final group = (created as CreateGroupSuccess).group;
      database.groups[database.groups.indexWhere(
        (item) => item.id == group.id,
      )] = group.copyWith(
        startsAt: sampleNow.add(const Duration(minutes: 30)),
      );

      final guest = await groups.join(
        group.id,
        participantUserId: 'user-bia',
        participantName: 'Bia',
        markAsLocalUser: false,
      );
      expect(guest, isA<JoinSuccess>());

      final leave = await groups.leave(group.id, userId: 'user-ana');
      expect(leave, isA<LeaveGroupFailure>());
      expect(
        (leave as LeaveGroupFailure).reason,
        LeaveGroupFailureReason.creatorMustDelete,
      );

      final deleted = await groups.deleteGroup(group.id, userId: 'user-ana');
      expect(deleted, isA<DeleteGroupSuccess>());
      final cancelled = (deleted as DeleteGroupSuccess).group;
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.filledSpots, 0);
      for (final person in cancelled.participants) {
        expect(person.refund, RefundStatus.refunded);
        expect(person.refundReason, RefundReason.organizerCancelledEvent);
      }

      final listed = await groups.listByCity(SampleIds.portoAlegre);
      expect(listed.map((item) => item.id), isNot(contains(group.id)));
      final mine = await groups.listForUser('user-bia');
      expect(mine.map((item) => item.id), contains(group.id));

      final again = await groups.deleteGroup(group.id, userId: 'user-ana');
      expect(
        (again as DeleteGroupFailure).reason,
        DeleteGroupFailureReason.alreadyCancelled,
      );
    },
  );

  test('a started session cannot be deleted or lose a participant', () async {
    final created = await groups.create(
      _request(
        extraSpots: 2,
        creatorUserId: 'user-ana',
        creatorDisplayName: 'Ana',
      ),
    );
    final group = (created as CreateGroupSuccess).group;
    final guest = await groups.join(
      group.id,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    final memberId = (guest as JoinSuccess).group.participants
        .firstWhere((person) => person.userId == 'user-bia')
        .id;
    _shift(database, group.id, sampleNow.subtract(const Duration(minutes: 10)));

    final removed = await groups.removeMember(
      group.id,
      actorUserId: 'user-ana',
      memberId: memberId,
    );
    expect(
      (removed as RemoveMemberFailure).reason,
      RemoveMemberFailureReason.sessionStarted,
    );
    expect(
      GroupMessages.removeFailure(RemoveMemberFailureReason.sessionStarted),
      'A sessão já começou.',
    );

    final deleted = await groups.deleteGroup(group.id, userId: 'user-ana');
    expect(
      (deleted as DeleteGroupFailure).reason,
      DeleteGroupFailureReason.sessionStarted,
    );
    final still = await groups.getById(group.id);
    expect(still!.isCancelled, isFalse);
    expect(still.participantForUser('user-bia')!.occupiesSeat, isTrue);
    expect(still.filledSpots, 2);

    _shift(database, group.id, sampleNow.subtract(const Duration(hours: 3)));
    final ended = await groups.deleteGroup(group.id, userId: 'user-ana');
    expect(
      (ended as DeleteGroupFailure).reason,
      DeleteGroupFailureReason.sessionEnded,
    );
  });

  test('a non-creator cannot delete a group', () async {
    final result = await groups.deleteGroup(
      SampleIds.groupSpCoberturaOpen,
      userId: 'user-local',
    );
    expect(result, isA<DeleteGroupFailure>());
    expect(
      (result as DeleteGroupFailure).reason,
      DeleteGroupFailureReason.notCreator,
    );
    final listed = await groups.listByCity(SampleIds.saoPaulo);
    expect(
      listed.map((group) => group.id),
      contains(SampleIds.groupSpCoberturaOpen),
    );
  });

  test('removing a participant refunds them and frees the seat', () async {
    final created = await groups.create(
      _request(
        extraSpots: 2,
        creatorUserId: 'user-ana',
        creatorDisplayName: 'Ana',
      ),
    );
    final group = (created as CreateGroupSuccess).group;
    final guest = await groups.join(
      group.id,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    final memberId = (guest as JoinSuccess).group.participants
        .firstWhere((person) => person.userId == 'user-bia')
        .id;

    final removed = await groups.removeMember(
      group.id,
      actorUserId: 'user-ana',
      memberId: memberId,
    );
    final updated = (removed as RemoveMemberSuccess).group;
    final bia = updated.participantForUser('user-bia')!;
    expect(bia.refundReason, RefundReason.organizerRemovedMember);
    expect(updated.filledSpots, 1);

    final replacement = await groups.join(
      group.id,
      participantUserId: 'user-caio',
      participantName: 'Caio',
      markAsLocalUser: false,
    );
    expect(replacement, isA<JoinSuccess>());
    expect((replacement as JoinSuccess).group.filledSpots, 2);
  });

  test('the same person cannot sit in two overlapping groups', () async {
    _shift(
      database,
      SampleIds.groupSpMetroAlmost,
      sampleNow.add(const Duration(hours: 5)),
    );
    _shift(
      database,
      SampleIds.groupSpCoberturaOpen,
      sampleNow.add(const Duration(hours: 5, minutes: 30)),
    );

    final first = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(first, isA<JoinSuccess>());
    final second = await groups.join(
      SampleIds.groupSpCoberturaOpen,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(second, isA<JoinFailure>());
    expect(
      (second as JoinFailure).reason,
      JoinFailureReason.overlapsAnotherGroup,
    );
    final cobertura = await groups.getById(SampleIds.groupSpCoberturaOpen);
    expect(cobertura!.joinedByMe, isFalse);
  });

  test('a group that already started cannot be joined or created', () async {
    _shift(
      database,
      SampleIds.groupSpCoberturaOpen,
      sampleNow.subtract(const Duration(minutes: 10)),
    );
    final join = await groups.join(
      SampleIds.groupSpCoberturaOpen,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect((join as JoinFailure).reason, JoinFailureReason.alreadyStarted);

    final pastSlot = database.slots.firstWhere(
      (slot) => slot.id == SampleIds.slotSpMetroPast,
    );
    expect(pastSlot.startsAt.isBefore(sampleNow), isTrue);
    final created = await groups.create(
      CreateGroupRequest(
        cityId: SampleIds.saoPaulo,
        houseId: SampleIds.houseSpAugusta,
        roomId: SampleIds.roomSpMetro,
        slotId: pastSlot.id,
        extraSpots: 2,
        creatorUserId: 'user-local',
        creatorDisplayName: 'Você',
      ),
    );
    expect(
      (created as CreateGroupFailure).reason,
      CreateGroupFailureReason.alreadyStarted,
    );
  });

  test(
    'an ended group leaves the city list and stays on the member history',
    () async {
      final joined = await groups.join(
        SampleIds.groupSpCoberturaOpen,
        participantUserId: 'user-local',
        participantName: 'Você',
      );
      expect(joined, isA<JoinSuccess>());
      final current = database.groups.firstWhere(
        (group) => group.id == SampleIds.groupSpCoberturaOpen,
      );
      _shift(
        database,
        current.id,
        sampleNow.subtract(Duration(minutes: current.durationMinutes + 5)),
      );

      final listed = await groups.listByCity(SampleIds.saoPaulo);
      expect(
        listed.map((group) => group.id),
        isNot(contains(SampleIds.groupSpCoberturaOpen)),
      );
      final mine = await groups.listForUser('user-local');
      expect(mine.single.id, SampleIds.groupSpCoberturaOpen);
      final again = await groups.join(
        SampleIds.groupSpCoberturaOpen,
        participantUserId: 'user-local',
        participantName: 'Você',
      );
      expect((again as JoinFailure).reason, JoinFailureReason.sessionEnded);
    },
  );

  test('confirming attendance is stored and counted', () async {
    final joined = await groups.join(
      SampleIds.groupSpCoberturaOpen,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    final before = (joined as JoinSuccess).group.confirmedCount;
    final confirmed = await groups.confirmAttendance(
      SampleIds.groupSpCoberturaOpen,
      userId: 'user-local',
    );
    final group = (confirmed as ConfirmAttendanceSuccess).group;
    expect(group.participantForUser('user-local')!.isConfirmed, isTrue);
    expect(group.confirmedCount, before + 1);
  });

  test('the creator can edit the size and the note inside the room', () async {
    final created = await groups.create(
      _request(
        extraSpots: 2,
        creatorUserId: 'user-ana',
        creatorDisplayName: 'Ana',
      ),
    );
    final group = (created as CreateGroupSuccess).group;
    final tooSmall = await groups.edit(
      group.id,
      actorUserId: 'user-ana',
      totalSpots: 1,
      note: 'oi',
    );
    expect(
      (tooSmall as EditGroupFailure).reason,
      EditGroupFailureReason.belowMinimum,
    );

    final saved = await groups.edit(
      group.id,
      actorUserId: 'user-ana',
      totalSpots: group.roomCapacity,
      note: '  Levar documento  ',
    );
    final updated = (saved as EditGroupSuccess).group;
    expect(updated.totalSpots, group.roomCapacity);
    expect(updated.note, 'Levar documento');
  });

  test('edit uses the same occupied count as the group', () async {
    final created = await groups.create(
      _request(
        extraSpots: 2,
        creatorUserId: 'user-ana',
        creatorDisplayName: 'Ana',
      ),
    );
    final group = (created as CreateGroupSuccess).group;
    await groups.join(
      group.id,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    final index = database.groups.indexWhere((item) => item.id == group.id);
    final seated = database.groups[index];
    expect(seated.seatedCount, 2);
    database.groups[index] = seated.copyWith(filledSpots: 1);
    expect(database.groups[index].occupiedSpots, 2);

    final tooSmall = await groups.edit(
      group.id,
      actorUserId: 'user-ana',
      totalSpots: 1,
      note: '',
    );
    expect(
      (tooSmall as EditGroupFailure).reason,
      EditGroupFailureReason.belowOccupancy,
    );

    database.groups[index] = database.groups[index].copyWith(filledSpots: 4);
    expect(database.groups[index].occupiedSpots, 4);
    final belowStored = await groups.edit(
      group.id,
      actorUserId: 'user-ana',
      totalSpots: 3,
      note: '',
    );
    expect(
      (belowStored as EditGroupFailure).reason,
      EditGroupFailureReason.belowOccupancy,
    );
  });
}

Future<void> _expectRefund(
  FakeGroupRepository groups,
  FakeDatabase database,
  DateTime startsAt,
  RefundStatus status,
  RefundReason reason,
) async {
  final id = SampleIds.groupSpCoberturaOpen;
  _shift(database, id, startsAt);
  final index = database.groups.indexWhere((group) => group.id == id);
  final current = database.groups[index];
  database.groups[index] = current.copyWith(
    participants: current.participants
        .where((person) => person.userId != 'user-local')
        .toList(),
    filledSpots: current.participants
        .where((person) => person.userId != 'user-local' && person.occupiesSeat)
        .length,
  );
  final joined = await groups.join(
    id,
    participantUserId: 'user-local',
    participantName: 'Você',
  );
  expect(joined, isA<JoinSuccess>(), reason: '$startsAt');
  final left = await groups.leave(id, userId: 'user-local');
  final me = (left as LeaveGroupSuccess).group.participantForUser(
    'user-local',
  )!;
  expect(me.refund, status);
  expect(me.refundReason, reason);
}

void _shift(FakeDatabase database, String id, DateTime startsAt) {
  final index = database.groups.indexWhere((group) => group.id == id);
  database.groups[index] = database.groups[index].copyWith(startsAt: startsAt);
}

CreateGroupRequest _request({
  required int extraSpots,
  required String creatorUserId,
  required String creatorDisplayName,
}) {
  return CreateGroupRequest(
    cityId: SampleIds.portoAlegre,
    houseId: SampleIds.housePoaRedencao,
    roomId: SampleIds.roomPoaEstufa,
    slotId: SampleIds.slotPoaEstufaFree,
    extraSpots: extraSpots,
    creatorUserId: creatorUserId,
    creatorDisplayName: creatorDisplayName,
  );
}
