import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('the phone keeps the bottom bar and the group window', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(AppKeys.groupWindow), findsOneWidget);
    expect(find.byType(ScapeLogo), findsOneWidget);
    expect(tester.getSize(find.byKey(AppKeys.groupSearch)).width, lessThan(520));

    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(find.text('O Cofre do Café'));
    final action = tester.getTopLeft(
      find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre)),
    );
    expect(action.dy, greaterThan(title.dy + 40));
  });

  testWidgets('desktop opens a site with a top nav, a grid and a side column', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(ScapeLogo), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(AppKeys.homeTab)).dy, lessThan(72));
    expect(
      tester.getCenter(find.byKey(AppKeys.homeTab)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.nearTab)).dx),
    );
    expect(find.byKey(AppKeys.groupWindow), findsNothing);
    expect(
      tester.getSize(find.byKey(AppKeys.groupSearch)).width,
      greaterThan(700),
    );

    final cards = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('group-card-');
      }),
    );
    expect(cards, findsWidgets);
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect((first.top - second.top).abs(), lessThan(2));
    expect((first.left - second.left).abs(), greaterThan(200));

    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(find.text('O Cofre do Café'));
    final action = tester.getTopLeft(
      find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre)),
    );
    expect(action.dx, greaterThan(title.dx + 200));

    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byKey(AppKeys.mapSheet));
    final map = tester.getRect(find.byType(FlutterMap));
    expect(sheet.right, lessThanOrEqualTo(map.left + 1));
    expect(map.right, closeTo(1280, 2));
  });
}
