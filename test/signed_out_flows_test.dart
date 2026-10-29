import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test('only account, my groups and create are safe return paths', () {
    expect(afterAuthLocation(null), '/');
    expect(afterAuthLocation('/account'), '/account');
    expect(afterAuthLocation('/groups/mine'), '/groups/mine');
    expect(afterAuthLocation('/groups/new'), '/groups/new');
    expect(
      afterAuthLocation('/groups/new?roomId=room-1'),
      '/groups/new?roomId=room-1',
    );
    expect(afterAuthLocation('https://example.invalid'), '/');
    expect(afterAuthLocation('/groups/other'), '/');
  });

  testWidgets('sign out, open an invite, log in and land in the group', (
    tester,
  ) async {
    final clock = FixedClock(sampleNow);
    final database = buildSampleDatabase(now: sampleNow);
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(clock),
        fakeDatabaseProvider.overrideWithValue(database),
        groupRepositoryProvider.overrideWithValue(groups),
      ],
    );
    await _signOut(tester);

    GoRouter.of(tester.element(find.byType(AccountScreen)))
        .go('/convite/${SampleIds.groupSpCoberturaOpen}');
    await tester.pumpAndSettle();
    expect(find.text('Cobertura da Paulista'), findsWidgets);
    await tester.tap(find.byKey(AppKeys.participate));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await _logInAsNicolas(tester);
    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(
      ProviderScope.containerOf(
        tester.element(find.text(GroupMessages.joinedBanner)),
      ).read(pendingInviteStoreProvider).groupId,
      isNull,
    );
  });

  testWidgets('logged-out Meus grupos asks for a session', (tester) async {
    await pumpScapeMatch(tester);
    await _signOut(tester);
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.signInToSeeGroups), findsOneWidget);
    expect(find.byKey(AppKeys.myGroupsUpcoming), findsNothing);
    expect(find.text('Cobertura da Paulista'), findsNothing);

    await tester.tap(find.byKey(AppKeys.myGroupsSignIn));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await _logInAsNicolas(tester);
    expect(find.byKey(AppKeys.myGroupsUpcoming), findsOneWidget);
  });

  testWidgets('logged-out Criar grupo opens login and returns to the form', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _signOut(tester);
    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CreateGroupScreen), findsNothing);
    await _logInAsNicolas(tester);
    expect(find.byType(CreateGroupScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}

Future<void> _signOut(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  final scrollable = find.descendant(
    of: find.byType(AccountScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    ),
  );
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.accountSignOut),
    200,
    scrollable: scrollable,
  );
  await tester.tap(find.byKey(AppKeys.accountSignOut));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.dialogConfirm));
  await tester.pumpAndSettle();
  expect(find.text(AccountMessages.signedOutTitle), findsOneWidget);
}

Future<void> _logInAsNicolas(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(AppKeys.loginEmail),
    'nicolas@exemplo.invalid',
  );
  await tester.enterText(find.byKey(AppKeys.loginPassword), 'senha-exemplo');
  await tester.tap(find.byKey(AppKeys.loginSubmit));
  await tester.pumpAndSettle();
}
