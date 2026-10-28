import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/my_groups_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the app opens on Home, with Meus grupos to its right', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(MyGroupsScreen), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(AppKeys.groupSearch), findsOneWidget);
    expect(find.byKey(AppKeys.newsFeed), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect((bar.destinations[0] as NavigationDestination).label, 'Home');
    expect((bar.destinations[1] as NavigationDestination).label, 'Meus grupos');
    expect((bar.destinations[2] as NavigationDestination).label, 'Conta');
    expect(
      tester.getCenter(find.byKey(AppKeys.homeTab)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.myGroups)).dx),
    );
    expect(
      tester.getCenter(find.byKey(AppKeys.myGroups)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.accountTab)).dx),
    );

    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();

    expect(find.byType(MyGroupsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(AppKeys.myGroupsUpcoming), findsOneWidget);
    expect(find.byKey(AppKeys.myGroupsPast), findsOneWidget);
    expect(find.byKey(AppKeys.myGroupsCancelled), findsOneWidget);
    expect(find.text('Próximos'), findsOneWidget);
    expect(find.text('Passados'), findsOneWidget);
    expect(find.text('Cancelados'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(MyGroupsScreen), findsNothing);
    expect(find.byKey(AppKeys.newsFeed), findsOneWidget);
  });

  testWidgets('create group and the old /groups path stay reachable', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/groups');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      GoRouterState.of(tester.element(find.byType(HomeScreen))).uri.path,
      '/',
    );
  });
}
