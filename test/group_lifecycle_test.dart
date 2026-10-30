import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/community/presentation/notice_screen.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test(
    'a group below the minimum is not ready, and the portal phase stays',
    () {
      final now = DateTime(2026, 10, 30, 12);
      final forming = _group(
        filled: 2,
        minimum: 6,
        closesAt: now.add(const Duration(days: 1)),
      );
      expect(forming.phaseAt(now), GroupPhase.forming);
      expect(forming.spotsUntilClose, 4);
      expect(
        GroupMessages.phaseLabel(forming.phaseAt(now), missing: 4),
        'Faltam 4 para fechar',
      );

      final ready = _group(
        filled: 6,
        minimum: 6,
        closesAt: now.add(const Duration(days: 1)),
      );
      expect(ready.phaseAt(now), GroupPhase.readyToReserve);

      final waiting = ready.copyWith(phaseOverride: GroupPhase.awaitingHouse);
      expect(waiting.phaseAt(now), GroupPhase.awaitingHouse);
      expect(
        GroupRules.missedMinimum(
          alreadyCancelled: false,
          portalOwned: true,
          filledSpots: 1,
          minimumSpots: 6,
          closesAt: now.subtract(const Duration(hours: 1)),
          startsAt: now.add(const Duration(days: 2)),
          now: now,
        ),
        isFalse,
      );
    },
  );

  test('three no-shows in 60 days restrict the next join', () {
    final now = DateTime(2026, 10, 30);
    final dates = [
      now.subtract(const Duration(days: 10)),
      now.subtract(const Duration(days: 5)),
      now.subtract(const Duration(days: 1)),
    ];
    expect(GroupRules.joinRestricted(dates, now), isTrue);
    expect(GroupRules.joinRestricted(dates.sublist(0, 2), now), isFalse);
    expect(
      GroupRules.isAdult(birthDate: DateTime(2010, 1, 1), now: now),
      isFalse,
    );
    expect(
      GroupRules.isAdult(birthDate: DateTime(1990, 1, 1), now: now),
      isTrue,
    );
  });

  test('a house window replaces the fixed two hours', () {
    final start = DateTime(2026, 10, 30, 18);
    final now = start.subtract(const Duration(hours: 3));
    expect(
      GroupRules.refundsOnParticipantCancel(startsAt: start, now: now),
      isTrue,
    );
    expect(
      GroupRules.refundsOnParticipantCancel(
        startsAt: start,
        now: now,
        window: const Duration(hours: 24),
      ),
      isFalse,
    );
  });

  test(
    'missing the close deadline cancels the group and refunds everyone',
    () async {
      final now = sampleNow;
      final database = buildSampleDatabase(now: now);
      final groups = FakeGroupRepository(
        database,
        clock: FixedClock(now),
        latency: Duration.zero,
      );
      final closed = await groups.getById('grp-cwb-cofre-missed');
      expect(closed, isNotNull);
      expect(closed!.isCancelled, isTrue);
      expect(
        closed.participants.every(
          (person) => person.refundReason == RefundReason.groupDidNotClose,
        ),
        isTrue,
      );
      final listed = await groups.listByCity(SampleIds.curitiba);
      expect(
        listed.any((group) => group.id == 'grp-cwb-cofre-missed'),
        isFalse,
      );
    },
  );

  test('the creator block stops a join', () async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
    );
    groups.board.block('user-marina', 'user-bia');
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(
      participants: [
        for (final person in current.participants)
          if (person.isCreator)
            Participant(
              id: person.id,
              userId: 'user-marina',
              displayName: person.displayName,
              isCreator: true,
              isLocalUser: false,
            )
          else
            person,
      ],
    );
    final blocked = await groups.join(
      SampleIds.groupCwbCofreAlmost,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    expect(blocked, isA<JoinFailure>());
    expect((blocked as JoinFailure).reason, JoinFailureReason.blocked);
  });

  testWidgets('the home cofre card says one person is missing to close', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    expect(find.text('Falta 1 para fechar'), findsWidgets);
    expect(find.text('Quase cheios'), findsNothing);
  });

  testWidgets('signup blocks a minor and a missing acceptance', (tester) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
      ],
    );
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/cadastro');
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.signupName), 'Teen');
    await tester.enterText(
      find.byKey(AppKeys.signupEmail),
      'teen@exemplo.invalid',
    );
    await tester.enterText(find.byKey(AppKeys.signupPassword), 'senha');
    await tester.enterText(find.byKey(AppKeys.signupBirthDay), '1');
    await tester.enterText(find.byKey(AppKeys.signupBirthMonth), '1');
    await tester.enterText(find.byKey(AppKeys.signupBirthYear), '2015');
    await tester.ensureVisible(find.byKey(AppKeys.signupTerms));
    await tester.tap(find.byKey(AppKeys.signupTerms));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppKeys.signupSubmit));
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.under18), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.signupBirthYear), '1990');
    await tester.tap(find.byKey(AppKeys.signupTerms));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppKeys.signupSubmit));
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.termsRequired), findsOneWidget);
  });

  testWidgets('the group detail shows the address and the map buttons', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(find.byKey(AppKeys.openMaps), findsOneWidget);
    expect(find.byKey(AppKeys.openWaze), findsOneWidget);
    expect(find.textContaining('Rua de exemplo'), findsOneWidget);
    expect(find.text('Falta 1 para fechar'), findsOneWidget);
    expect(find.textContaining('Prazo para fechar'), findsOneWidget);
  });

  test('copyWith can clear the close deadline and the portal phase', () {
    final now = DateTime(2026, 10, 30, 12);
    final group = _group(
      filled: 6,
      minimum: 6,
      closesAt: now.add(const Duration(days: 1)),
    ).copyWith(phaseOverride: GroupPhase.awaitingHouse);
    final cleared = group.copyWith(closesAt: null, phaseOverride: null);
    expect(cleared.closesAt, isNull);
    expect(cleared.phaseOverride, isNull);
    expect(
      cleared.closesAtResolved,
      cleared.startsAt.subtract(const Duration(hours: 1)),
    );
    expect(group.showCloseDeadline(now), isFalse);
    final forming = _group(
      filled: 2,
      minimum: 6,
      closesAt: now.subtract(const Duration(hours: 3)),
    ).copyWith(startsAt: now.subtract(const Duration(minutes: 20)));
    expect(
      GroupMessages.phaseLabel(
        forming.phaseAt(now),
        missing: forming.spotsUntilClose,
        started: true,
      ),
      'Sessão já começou',
    );
    expect(forming.showCloseDeadline(now), isFalse);
  });

  test('signup stores the birth date', () async {
    final auth = FakeAuthRepository(signedIn: null);
    final birth = DateTime(1990, 4, 2);
    final error = await auth.signUp(
      name: 'Ana',
      email: 'ana@exemplo.invalid',
      password: 'senha',
      birthDate: birth,
      now: sampleNow,
      acceptedTerms: true,
    );
    expect(error, isNull);
    expect(auth.signedInUser?.birthDate, birth);
  });

  test('openExternalUrl fails closed when nothing can launch', () async {
    final opened = await openExternalUrl(
      Uri.parse('https://exemplo.invalid/mapa'),
    );
    expect(opened, isFalse);
  });

  test(
    'the payment reminder follows its own window and each user keeps a pref',
    () {
      final now = sampleNow;
      final board = CommunityBoard();
      final soon = _memberGroup(
        id: 'g-soon',
        startsAt: now.add(const Duration(hours: 10)),
        closesAt: now.add(const Duration(hours: 4)),
        userId: 'user-local',
      );
      final imminent = _memberGroup(
        id: 'g-imminent',
        startsAt: now.add(const Duration(minutes: 90)),
        closesAt: now.add(const Duration(minutes: 30)),
        userId: 'user-local',
      );
      board.syncReminders(
        groups: [soon, imminent],
        userId: 'user-local',
        now: now,
      );
      final bias = _memberGroup(
        id: 'g-bia',
        startsAt: now.add(const Duration(hours: 10)),
        closesAt: now.add(const Duration(hours: 4)),
        userId: 'user-bia',
      );
      board.syncReminders(groups: [bias], userId: 'user-bia', now: now);
      final mine = board.visibleFor('user-local');
      expect(
        mine.any((notice) => notice.kind == NoticeKind.reminder24h),
        isTrue,
      );
      expect(
        mine.any((notice) => notice.kind == NoticeKind.reminder2h),
        isTrue,
      );
      expect(
        mine
            .where((notice) => notice.kind == NoticeKind.paymentDeadline)
            .length,
        2,
      );
      board.setPref('user-local', NoticeKind.paymentDeadline, false);
      expect(
        board
            .visibleFor('user-local')
            .any((notice) => notice.kind == NoticeKind.paymentDeadline),
        isFalse,
      );
      expect(
        board
            .visibleFor('user-bia')
            .any((notice) => notice.kind == NoticeKind.paymentDeadline),
        isTrue,
      );
    },
  );

  test(
    'a group created inside 24 hours closes one hour before the start',
    () async {
      final now = sampleNow;
      final database = buildSampleDatabase(now: now);
      final room = database.roomById(SampleIds.roomSpCobertura)!;
      final house = database.houseById(room.houseId)!;
      final start = now.add(const Duration(hours: 5));
      final slot = TimeSlot(
        id: 'slot-short-lead',
        roomId: room.id,
        startsAt: start,
      );
      final custom = _withSlot(database, slot);
      final groups = FakeGroupRepository(
        custom,
        clock: FixedClock(now),
        latency: Duration.zero,
      );
      final created = await groups.create(
        CreateGroupRequest(
          cityId: house.cityId,
          houseId: house.id,
          roomId: room.id,
          slotId: slot.id,
          extraSpots: 1,
          creatorUserId: 'user-ana',
          creatorDisplayName: 'Ana',
        ),
      );
      final group = (created as CreateGroupSuccess).group;
      expect(group.closesAt, start.subtract(const Duration(hours: 1)));

      final farStart = now.add(const Duration(hours: 48));
      final farSlot = TimeSlot(
        id: 'slot-long-lead',
        roomId: room.id,
        startsAt: farStart,
      );
      final carried = FakeDatabase(
        cities: custom.cities,
        houses: custom.houses,
        rooms: custom.rooms,
        slots: [...custom.slots, farSlot],
        groups: custom.groups,
      );
      final laterCreate = FakeGroupRepository(
        carried,
        clock: FixedClock(now),
        latency: Duration.zero,
      );
      final far = await laterCreate.create(
        CreateGroupRequest(
          cityId: house.cityId,
          houseId: house.id,
          roomId: room.id,
          slotId: farSlot.id,
          extraSpots: 1,
          creatorUserId: 'user-bia',
          creatorDisplayName: 'Bia',
        ),
      );
      expect(
        (far as CreateGroupSuccess).group.closesAt,
        farStart.subtract(const Duration(hours: 24)),
      );

      final atDeadline = FakeGroupRepository(
        custom,
        clock: FixedClock(group.closesAt!),
        latency: Duration.zero,
      );
      final closed = await atDeadline.getById(group.id);
      expect(closed!.isCancelled, isTrue);
      expect(
        closed.participants.every(
          (person) => person.refundReason == RefundReason.groupDidNotClose,
        ),
        isTrue,
      );
    },
  );

  test('create and edit reject a total below the room minimum', () async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
    );
    final room = database.roomById(SampleIds.roomCwbCofre)!;
    final house = database.houseById(room.houseId)!;
    final slot = TimeSlot(
      id: 'slot-cofre-small',
      roomId: room.id,
      startsAt: now.add(const Duration(hours: 30)),
    );
    final custom = _withSlot(database, slot);
    final repo = FakeGroupRepository(
      custom,
      clock: FixedClock(now),
      latency: Duration.zero,
    );
    final created = await repo.create(
      CreateGroupRequest(
        cityId: house.cityId,
        houseId: house.id,
        roomId: room.id,
        slotId: slot.id,
        extraSpots: 1,
        creatorUserId: 'user-ana',
        creatorDisplayName: 'Ana',
      ),
    );
    expect(created, isA<CreateGroupFailure>());
    expect(
      (created as CreateGroupFailure).reason,
      CreateGroupFailureReason.belowRoomMinimum,
    );

    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(
      participants: [
        for (final person in current.participants)
          if (person.isCreator) _withUser(person, 'user-marina') else person,
      ],
    );
    final edited = await groups.edit(
      SampleIds.groupCwbCofreAlmost,
      actorUserId: 'user-marina',
      totalSpots: 5,
      note: '',
    );
    expect(
      (edited as EditGroupFailure).reason,
      EditGroupFailureReason.belowRoomMinimum,
    );
  });

  test('the offered seat stays reserved, accept joins, and an expired offer moves on', () async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final board = CommunityBoard();
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
      board: board,
    );
    _setCreator(database, SampleIds.groupCwbCofreAlmost, 'user-marina');
    final filled = await groups.join(
      SampleIds.groupCwbCofreAlmost,
      participantUserId: 'user-fill',
      participantName: 'Fill',
      markAsLocalUser: false,
    );
    expect(filled, isA<JoinSuccess>());
    expect(
      await groups.joinWaitlist(
        groupId: SampleIds.groupCwbCofreAlmost,
        userId: 'user-bia',
        displayName: 'Bia',
      ),
      isNull,
    );
    expect(
      await groups.joinWaitlist(
        groupId: SampleIds.groupCwbCofreAlmost,
        userId: 'user-caio',
        displayName: 'Caio',
      ),
      isNull,
    );
    final seated = database.groups.firstWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final victim = seated.participants.firstWhere(
      (person) => !person.isCreator,
    );
    final removed = await groups.removeMember(
      SampleIds.groupCwbCofreAlmost,
      actorUserId: 'user-marina',
      memberId: victim.id,
    );
    expect(removed, isA<RemoveMemberSuccess>());
    expect(
      board.offerStillOpen(
        board.entryFor(SampleIds.groupCwbCofreAlmost, 'user-bia')!,
        now,
      ),
      isTrue,
    );
    final sneak = await groups.join(
      SampleIds.groupCwbCofreAlmost,
      participantUserId: 'user-duda',
      participantName: 'Duda',
      markAsLocalUser: false,
    );
    expect((sneak as JoinFailure).reason, JoinFailureReason.seatReserved);

    final accepted = await groups.acceptWaitlist(
      groupId: SampleIds.groupCwbCofreAlmost,
      userId: 'user-bia',
      displayName: 'Bia',
    );
    expect(accepted, isA<JoinSuccess>());
    expect(
      (accepted as JoinSuccess).group.participantForUser('user-bia'),
      isNotNull,
    );

    expect(
      await groups.joinWaitlist(
        groupId: SampleIds.groupCwbCofreAlmost,
        userId: 'user-eva',
        displayName: 'Eva',
      ),
      isNull,
    );
    final again = database.groups.firstWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final nextVictim = again.participants.firstWhere(
      (person) =>
          person.occupiesSeat &&
          !person.isCreator &&
          person.userId != 'user-bia',
    );
    final removedAgain = await groups.removeMember(
      SampleIds.groupCwbCofreAlmost,
      actorUserId: 'user-marina',
      memberId: nextVictim.id,
    );
    expect(removedAgain, isA<RemoveMemberSuccess>());
    final laterNow = now.add(const Duration(hours: 2, minutes: 1));
    final later = FakeGroupRepository(
      database,
      clock: FixedClock(laterNow),
      latency: Duration.zero,
      board: board,
    );
    final expired = await later.acceptWaitlist(
      groupId: SampleIds.groupCwbCofreAlmost,
      userId: 'user-caio',
      displayName: 'Caio',
    );
    expect((expired as JoinFailure).reason, JoinFailureReason.offerExpired);
    expect(
      GroupMessages.joinFailure(JoinFailureReason.offerExpired),
      isNot(contains('cheio')),
    );
    expect(
      board.offerStillOpen(
        board.entryFor(SampleIds.groupCwbCofreAlmost, 'user-eva')!,
        laterNow,
      ),
      isTrue,
    );
  });

  test('a block by a regular member stops the join', () async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
    );
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(
      participants: [
        for (final person in current.participants)
          if (!person.isCreator && person.id.endsWith('p1'))
            _withUser(person, 'user-lia')
          else
            person,
      ],
    );
    groups.board.block('user-lia', 'user-bia');
    final blocked = await groups.join(
      SampleIds.groupCwbCofreAlmost,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    expect((blocked as JoinFailure).reason, JoinFailureReason.blocked);
  });

  testWidgets('a blocked person disappears from the home cards', (
    tester,
  ) async {
    final board = CommunityBoard();
    board.block(
      'user-local',
      CommunityBoard.personKey(seatId: 'grp-cwb-cofre-almost-p0'),
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        communityBoardProvider.overrideWithValue(board),
      ],
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      findsNothing,
    );
    expect(find.byType(GroupCard), findsWidgets);
  });

  testWidgets('the offered person accepts the seat on the group screen', (
    tester,
  ) async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final board = CommunityBoard();
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
      board: board,
    );
    await groups.joinWaitlist(
      groupId: SampleIds.groupCwbCofreAlmost,
      userId: 'user-local',
      displayName: 'Nícolas',
    );
    await groups.getById(SampleIds.groupCwbCofreAlmost);
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(now)),
        fakeDatabaseProvider.overrideWithValue(database),
        communityBoardProvider.overrideWithValue(board),
        groupRepositoryProvider.overrideWithValue(groups),
      ],
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
    );
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.waitlistAccept), findsOneWidget);
    expect(find.text(GroupMessages.waitlistDecline), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.waitlistAccept));
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
  });

  testWidgets(
    'a missed deadline uses the close banner, not the organizer one',
    (tester) async {
      await pumpScapeMatch(
        tester,
        overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/groups/grp-cwb-cofre-missed');
      await tester.pumpAndSettle();
      expect(find.text(GroupMessages.missedCloseBanner), findsOneWidget);
      expect(find.text(GroupMessages.cancelledBanner), findsNothing);
      expect(find.textContaining('Prazo para fechar'), findsNothing);
    },
  );

  testWidgets('account opens privacy and refund next to the terms', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/account');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppKeys.accountPrivacy));
    await tester.tap(find.byKey(AppKeys.accountPrivacy));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.privacyTitle), findsOneWidget);
    router.go('/account');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppKeys.accountRefund));
    await tester.tap(find.byKey(AppKeys.accountRefund));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.refundTitle), findsOneWidget);
  });

  testWidgets('turning off a notice pref hides it for this account', (
    tester,
  ) async {
    final board = CommunityBoard();
    board.notices.add(
      AppNotice(
        id: 'paymentDeadline-user-local-g',
        userId: 'user-local',
        kind: NoticeKind.paymentDeadline,
        title: 'Sala do Cofre perto do prazo',
        body: 'Sala de exemplo',
        at: sampleNow,
      ),
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        communityBoardProvider.overrideWithValue(board),
        groupRepositoryProvider.overrideWithValue(
          FakeGroupRepository(
            loadSampleDatabase(),
            clock: FixedClock(sampleNow),
            latency: Duration.zero,
            board: board,
          ),
        ),
      ],
    );
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/account/notices');
    await tester.pumpAndSettle();
    expect(find.text('Sala do Cofre perto do prazo'), findsOneWidget);
    await tester.tap(
      find.byKey(AppKeys.noticePref(NoticeKind.paymentDeadline.name)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sala do Cofre perto do prazo'), findsNothing);
  });

  test('creating a group inside the last hour is refused', () async {
    final now = sampleNow;
    final inside = await _createAt(
      now,
      now.add(const Duration(minutes: 40)),
      'slot-inside-hour',
    );
    expect(inside, isA<CreateGroupFailure>());
    expect(
      (inside as CreateGroupFailure).reason,
      CreateGroupFailureReason.tooCloseToStart,
    );
    expect(
      GroupMessages.createFailure(CreateGroupFailureReason.tooCloseToStart),
      contains('1 h'),
    );

    final exact = await _createAt(
      now,
      now.add(const Duration(hours: 1)),
      'slot-exact-hour',
    );
    expect(
      (exact as CreateGroupFailure).reason,
      CreateGroupFailureReason.tooCloseToStart,
    );

    final ok = await _createAt(
      now,
      now.add(const Duration(hours: 1, minutes: 1)),
      'slot-just-over-hour',
    );
    final group = (ok as CreateGroupSuccess).group;
    expect(group.closesAt, group.startsAt.subtract(const Duration(hours: 1)));
    expect(group.isCancelled, isFalse);
  });

  test('the refund draft leaves no-shows for the house', () {
    expect(LegalDocuments.refundBody, isNot(contains('acumula falta')));
    expect(LegalDocuments.refundBody, contains('marcada pela casa'));
  });

  test('the home window height follows the cards still on screen', () {
    expect(groupWindowHeightFor(1), double.infinity);
    expect(groupWindowHeightFor(2), groupWindowMaxHeight);
  });

  testWidgets('a reserved seat still offers the waitlist', (tester) async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final board = CommunityBoard();
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
      board: board,
    );
    await groups.joinWaitlist(
      groupId: SampleIds.groupCwbCofreAlmost,
      userId: 'user-bia',
      displayName: 'Bia',
    );
    await groups.getById(SampleIds.groupCwbCofreAlmost);
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(now)),
        fakeDatabaseProvider.overrideWithValue(database),
        communityBoardProvider.overrideWithValue(board),
        groupRepositoryProvider.overrideWithValue(groups),
      ],
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
    );
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.seatReserved), findsOneWidget);
    expect(find.byKey(AppKeys.joinWaitlist), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.joinWaitlist));
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.waitlistJoined), findsOneWidget);
  });

  testWidgets('opening notices syncs reminders without Meus grupos', (
    tester,
  ) async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    _setCreator(database, SampleIds.groupCwbCofreAlmost, 'user-local');
    final board = CommunityBoard();
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
      board: board,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          clockProvider.overrideWithValue(FixedClock(now)),
          fakeDatabaseProvider.overrideWithValue(database),
          communityBoardProvider.overrideWithValue(board),
          groupRepositoryProvider.overrideWithValue(groups),
        ],
        child: const MaterialApp(home: NoticeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('está perto'), findsOneWidget);
  });
}

Group _group({
  required int filled,
  required int minimum,
  required DateTime closesAt,
}) {
  return Group(
    id: 'g',
    cityId: 'c',
    cityName: 'Curitiba',
    houseId: 'h',
    houseName: 'Casa',
    neighborhood: 'Centro',
    roomId: 'r',
    roomName: 'Sala',
    roomTheme: 'Tema',
    roomCapacity: 8,
    durationMinutes: 60,
    difficulty: Difficulty.easy,
    slotId: 's',
    startsAt: closesAt.add(const Duration(days: 2)),
    filledSpots: filled,
    totalSpots: 8,
    participants: const [],
    priceCents: 1000,
    minimumSpots: minimum,
    closesAt: closesAt,
  );
}

FakeDatabase _withSlot(FakeDatabase database, TimeSlot slot) {
  return FakeDatabase(
    cities: database.cities,
    houses: database.houses,
    rooms: database.rooms,
    slots: [...database.slots, slot],
    groups: [...database.groups],
  );
}

void _setCreator(FakeDatabase database, String groupId, String userId) {
  final index = database.groups.indexWhere((group) => group.id == groupId);
  final current = database.groups[index];
  database.groups[index] = current.copyWith(
    participants: [
      for (final person in current.participants)
        if (person.isCreator) _withUser(person, userId) else person,
    ],
  );
}

Participant _withUser(Participant person, String userId) {
  return Participant(
    id: person.id,
    userId: userId,
    displayName: person.displayName,
    isCreator: person.isCreator,
    isLocalUser: person.isLocalUser,
    attendance: person.attendance,
    payment: person.payment,
    refund: person.refund,
    refundReason: person.refundReason,
  );
}

Future<CreateGroupResult> _createAt(
  DateTime now,
  DateTime start,
  String slotId,
) {
  final database = buildSampleDatabase(now: now);
  final room = database.roomById(SampleIds.roomSpCobertura)!;
  final house = database.houseById(room.houseId)!;
  final slot = TimeSlot(id: slotId, roomId: room.id, startsAt: start);
  final groups = FakeGroupRepository(
    _withSlot(database, slot),
    clock: FixedClock(now),
    latency: Duration.zero,
  );
  return groups.create(
    CreateGroupRequest(
      cityId: house.cityId,
      houseId: house.id,
      roomId: room.id,
      slotId: slot.id,
      extraSpots: 1,
      creatorUserId: 'user-ana',
      creatorDisplayName: 'Ana',
    ),
  );
}

Group _memberGroup({
  required String id,
  required DateTime startsAt,
  required DateTime closesAt,
  required String userId,
}) {
  return Group(
    id: id,
    cityId: 'c',
    cityName: 'Curitiba',
    houseId: 'h',
    houseName: 'Casa',
    neighborhood: 'Centro',
    roomId: 'r',
    roomName: 'Sala',
    roomTheme: 'Tema',
    roomCapacity: 8,
    durationMinutes: 60,
    difficulty: Difficulty.easy,
    slotId: 's',
    startsAt: startsAt,
    filledSpots: 1,
    totalSpots: 6,
    participants: [
      Participant(
        id: '$id-p',
        userId: userId,
        displayName: 'Pessoa',
        isCreator: true,
        isLocalUser: true,
      ),
    ],
    priceCents: 1000,
    minimumSpots: 4,
    closesAt: closesAt,
  );
}
