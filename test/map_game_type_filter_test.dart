import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/data/selected_game_type_store.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('map chips follow the shared game type and filter pins', (
    tester,
  ) async {
    await _openNear(tester, const Size(390, 844));

    for (final choice in GameTypes.choices) {
      expect(find.text(choice.shortLabel), findsWidgets);
    }
    expect(_chip(tester, 'Todos').selected, isTrue);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.byKey(AppKeys.nearbyCard('grp-cwb-porao-rpg')), findsOneWidget);

    final map = tester.getRect(find.byType(FlutterMap));
    final bar = tester.getRect(find.byKey(AppKeys.gameTypeChipBar));
    expect(map.contains(bar.center), isTrue);
    expect(bar.top, lessThan(map.top + 24));
    expect(bar.width, lessThan(390));

    final scroll = _chipScroll(tester);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Imersivo'), findsWidgets);
    expect(
      tester.getRect(find.widgetWithText(ChoiceChip, 'Imersivo')).right,
      lessThanOrEqualTo(bar.right + 1),
    );

    await tester.ensureVisible(
      find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)),
    );
    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
    await tester.pumpAndSettle();

    expect(_chip(tester, 'RPG').selected, isTrue);
    expect(_chip(tester, 'Todos').selected, isFalse);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsNothing);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.byKey(AppKeys.nearbyCard('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.byKey(AppKeys.nearbyCard('grp-curitiba-near-0')), findsNothing);
    expect(find.text('Mesa de RPG no porão'), findsWidgets);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byKey(AppKeys.gameTypeChipBar)),
      ).read(selectedGameTypeIdProvider),
      GameTypes.rpg,
    );

    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(AppKeys.gameTypeSelector),
        matching: find.text('RPG'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a saved preference filters the map before any tap', (
    tester,
  ) async {
    await _openNear(
      tester,
      const Size(1440, 900),
      savedGameTypeId: GameTypes.rpg,
    );

    expect(_chip(tester, 'RPG').selected, isTrue);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsNothing);
    expect(find.byKey(AppKeys.nearbyCard('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.text('Mesa de RPG no porão'), findsWidgets);

    final map = tester.getRect(find.byType(FlutterMap));
    final bar = tester.getRect(find.byKey(AppKeys.gameTypeChipBar));
    expect(map.contains(bar.center), isTrue);
    expect(bar.left, greaterThan(300));
    expect(find.byKey(AppKeys.gameTypeChipBar), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.boardGame)));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'Tabuleiro').selected, isTrue);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsNothing);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsNothing);
    expect(find.byKey(AppKeys.nearEmpty), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.escapeRoom)));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-rpg')), findsNothing);
    expect(_chip(tester, 'Escape').selected, isTrue);
  });
}

ChoiceChip _chip(WidgetTester tester, String label) {
  return tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
}

ScrollableState _chipScroll(WidgetTester tester) {
  final scroll = find.descendant(
    of: find.byKey(AppKeys.gameTypeChipBar),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  return tester.state<ScrollableState>(scroll);
}

Future<void> _openNear(
  WidgetTester tester,
  Size size, {
  String? savedGameTypeId,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpScapeMatch(
    tester,
    overrides: [
      mapTileProvider.overrideWithValue(MemoryTileProvider()),
      userLocationSourceProvider.overrideWithValue(
        FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
      ),
      if (savedGameTypeId != null)
        selectedGameTypeStoreProvider.overrideWithValue(
          SelectedGameTypeStore(savedGameTypeId: savedGameTypeId),
        ),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.nearTab));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pumpAndSettle();
}
