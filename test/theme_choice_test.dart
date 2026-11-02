import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/domain/theme_choice.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';

void main() {
  test('a missing theme follows the device', () async {
    SharedPreferences.setMockInitialValues({});
    final missing = ThemeChoiceStore();
    await missing.load();
    expect(missing.choice, ThemeChoice.system);

    SharedPreferences.setMockInitialValues({
      ThemeChoiceStore.storageKey: 'noite',
    });
    final unknown = ThemeChoiceStore();
    await unknown.load();
    expect(unknown.choice, ThemeChoice.system);
  });

  test('the chosen theme is restored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeChoiceStore();
    await store.persist(ThemeChoice.dark);
    final again = ThemeChoiceStore();
    await again.load();
    expect(again.choice, ThemeChoice.dark);

    await again.persist(ThemeChoice.light);
    final light = ThemeChoiceStore();
    await light.load();
    expect(light.choice, ThemeChoice.light);
  });

  testWidgets('a saved dark theme wins over a light device', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = ThemeChoiceStore();
    store.remember(ThemeChoice.dark);
    await pumpScapeMatch(
      tester,
      overrides: [themeChoiceStoreProvider.overrideWithValue(store)],
    );
    expect(_brightness(tester, find.byType(HomeScreen)), Brightness.dark);
  });

  testWidgets('settings switches the theme without leaving the page', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _openSettings(tester);
    expect(_brightness(tester, find.text('Aparência')), Brightness.light);

    await tester.tap(find.byKey(AppKeys.themeChoice('dark')));
    await tester.pumpAndSettle();
    expect(find.text('Configurações'), findsWidgets);
    expect(_brightness(tester, find.text('Aparência')), Brightness.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ThemeChoiceStore.storageKey), 'dark');

    await tester.tap(find.byKey(AppKeys.themeChoice('light')));
    await tester.pumpAndSettle();
    expect(_brightness(tester, find.text('Aparência')), Brightness.light);

    await tester.tap(find.byKey(AppKeys.themeChoice('system')));
    await tester.pumpAndSettle();
    expect(_brightness(tester, find.text('Aparência')), Brightness.light);
  });

  testWidgets('a signed-out person can open settings and darken the map', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.accountSignOut),
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(find.byKey(AppKeys.accountSignOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();
    expect(find.text(AccountMessages.signedOutTitle), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.accountSettings));
    await tester.pumpAndSettle();
    expect(find.text('Aparência'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.themeChoice('dark')));
    await tester.pumpAndSettle();
    expect(_brightness(tester, find.text('Aparência')), Brightness.dark);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(_brightness(tester, find.byType(FlutterMap)), Brightness.dark);
    expect(find.text('Carregando o mapa...'), findsNothing);
  });
}

Brightness _brightness(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).brightness;
}

Future<void> _openSettings(WidgetTester tester) async {
  await pumpScapeMatch(tester);
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountSettings));
  await tester.pumpAndSettle();
}
