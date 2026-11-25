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

    expect(GameTypes.choices.map((choice) => choice.id), [
      GameTypes.all,
      GameTypes.escapeRoom,
    ]);
    for (final choice in GameTypes.choices) {
      expect(find.text(choice.shortLabel), findsWidgets);
    }
    expect(_chip(tester, 'Todos').selected, isTrue);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-quase')), findsOneWidget);

    final map = tester.getRect(find.byType(FlutterMap));
    final bar = tester.getRect(find.byKey(AppKeys.gameTypeChipBar));
    expect(map.contains(bar.center), isTrue);
    expect(bar.top, lessThan(map.top + 24));
    expect(bar.width, lessThan(390));
    expect(
      tester.getRect(find.widgetWithText(ChoiceChip, 'Escape')).right,
      lessThanOrEqualTo(bar.right + 1),
    );

    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.escapeRoom)));
    await tester.pumpAndSettle();

    expect(_chip(tester, 'Escape').selected, isTrue);
    expect(_chip(tester, 'Todos').selected, isFalse);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-quase')), findsOneWidget);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byKey(AppKeys.gameTypeChipBar)),
      ).read(selectedGameTypeIdProvider),
      GameTypes.escapeRoom,
    );

    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(AppKeys.gameTypeSelector),
        matching: find.text('Escape'),
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
      savedGameTypeId: GameTypes.escapeRoom,
    );

    expect(_chip(tester, 'Escape').selected, isTrue);
    expect(_chip(tester, 'Todos').selected, isFalse);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-quase')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);

    final map = tester.getRect(find.byType(FlutterMap));
    final bar = tester.getRect(find.byKey(AppKeys.gameTypeChipBar));
    expect(map.contains(bar.center), isTrue);
    expect(bar.left, greaterThan(300));
    expect(find.byKey(AppKeys.gameTypeChipBar), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.all)));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'Todos').selected, isTrue);
    expect(find.byKey(AppKeys.mapPin('grp-curitiba-near-0')), findsOneWidget);
    expect(find.byKey(AppKeys.mapPin('grp-cwb-porao-quase')), findsOneWidget);
  });
}

ChoiceChip _chip(WidgetTester tester, String label) {
  return tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
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
