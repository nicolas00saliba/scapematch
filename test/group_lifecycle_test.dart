import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
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
