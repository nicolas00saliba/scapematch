import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/cities/data/selected_city_store.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the intro appears only the first time and skip hides it', (
    tester,
  ) async {
    final first = OnboardingStore(seen: false);
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      overrides: [onboardingStoreProvider.overrideWithValue(first)],
    );

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(OnboardingMessages.findBody), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Quase cheios'), findsNothing);

    await tester.tap(find.byKey(AppKeys.onboardingSkip));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(first.seen, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingStore.storageKey), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    final again = OnboardingStore();
    await again.load();
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      overrides: [onboardingStoreProvider.overrideWithValue(again)],
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Quase cheios'), findsNothing);
  });

  testWidgets('the chosen city is saved and Começar opens Home', (
    tester,
  ) async {
    final store = OnboardingStore(seen: false);
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
    );

    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.nearBody), findsOneWidget);
    expect(find.text('Curitiba'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.citySelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
    await tester.pumpAndSettle();
    expect(find.text('São Paulo'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.inviteBody), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.payBody), findsOneWidget);
    expect(find.byKey(AppKeys.onboardingStart), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.onboardingStart));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('São Paulo'), findsWidgets);
    expect(find.text('Quase cheios'), findsNothing);
    final saved = SelectedCityStore();
    await saved.load();
    expect(saved.resolve(), SampleIds.saoPaulo);
  });

  testWidgets('the intro fits a phone and a wide window', (tester) async {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final store = OnboardingStore(seen: false);
      await pumpScapeMatch(
        tester,
        showOnboarding: true,
        overrides: [onboardingStoreProvider.overrideWithValue(store)],
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size page 1');
      expect(find.byType(OnboardingScreen), findsOneWidget, reason: '$size');
      for (var step = 0; step < 3; step++) {
        final next = find.byKey(AppKeys.onboardingNext);
        expect(next, findsOneWidget, reason: '$size step $step');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$size page ${step + 2}',
        );
      }
      expect(find.byKey(AppKeys.onboardingStart), findsOneWidget);
    }
  });

  test('real opens on the intro until it is seen; demo never does', () {
    expect(introIsFirstScreen(mode: AppMode.real, seen: false), isTrue);
    expect(introIsFirstScreen(mode: AppMode.real, seen: true), isFalse);
    expect(introIsFirstScreen(mode: AppMode.demo, seen: false), isFalse);
    expect(showsIntroReplay(AppMode.real), isFalse);
    expect(showsIntroReplay(AppMode.demo), isTrue);
  });

  test('demo does not write the real intro flag', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    await prefs.remove(OnboardingStore.storageKey);

    final real = OnboardingStore(seen: false);
    await real.load();
    expect(real.seen, isFalse);

    final demo = OnboardingStore(persist: false, seen: false);
    await demo.markSeen();
    expect(demo.seen, isTrue);
    expect(prefs.getBool(OnboardingStore.storageKey), isNull);

    await real.markSeen();
    expect(prefs.getBool(OnboardingStore.storageKey), isTrue);
    final again = OnboardingStore();
    await again.load();
    expect(again.seen, isTrue);
  });

  testWidgets('real mode opens on the intro on phone and web', (tester) async {
    final store = OnboardingStore(seen: false);
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      onboardingMode: AppMode.real,
      overrides: [
        onboardingStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );

    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget, reason: '$size');
      expect(find.byType(HomeScreen), findsNothing, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
      if (size.width >= 960) {
        expect(
          tester.getTopLeft(find.text(OnboardingMessages.findTitle)).dx,
          greaterThan(size.width * 0.5),
          reason: '$size',
        );
        expect(find.byKey(AppKeys.onboardingBack), findsNothing);
      }
    }

    await tester.tap(find.byKey(AppKeys.onboardingSkip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.seen, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingStore.storageKey), isTrue);

    tester.view.physicalSize = const Size(400, 1800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountDestination('help')));
    await tester.pumpAndSettle();
    expect(find.text('Ajuda'), findsWidgets);
    expect(find.text(OnboardingMessages.replay), findsNothing);
    expect(find.byKey(AppKeys.accountIntro), findsNothing);
    expect(find.text('Como achar um grupo?'), findsOneWidget);
  });

  testWidgets('a direct invite in real mode skips the intro', (tester) async {
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      onboardingMode: AppMode.real,
      overrides: [
        onboardingStoreProvider.overrideWithValue(OnboardingStore(seen: false)),
      ],
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    GoRouter.of(tester.element(find.byType(OnboardingScreen)))
        .go('/convite/${SampleIds.groupCwbCofreAlmost}');
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Convite'), findsOneWidget);
  });

  testWidgets('demo opens on Home and Help can replay the intro', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(OnboardingStore.storageKey);
    final store = OnboardingStore(persist: false, seen: false);
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      onboardingMode: AppMode.demo,
      overrides: [
        onboardingStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(store.seen, isFalse);

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountDestination('help')));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.replay), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.accountIntro));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(OnboardingMessages.findBody), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.byKey(AppKeys.onboardingSkip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(store.seen, isTrue);
    expect(prefs.getBool(OnboardingStore.storageKey), isNull);
  });

  testWidgets('demo Help can replay the intro without an account', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      onboardingMode: AppMode.demo,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.accountDestination('help')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountIntro));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(OnboardingMessages.findBody), findsOneWidget);
    expect(find.byType(AccountScreen), findsNothing);

    await tester.tap(find.byKey(AppKeys.onboardingSkip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(selectedCityIdProvider),
      SampleIds.curitiba,
    );
  });

  test('the desktop frame keeps the photo aspect and the source pixels', () {
    final phone = fitOnboardingPhoto(
      maxWidth: 1400,
      maxHeight: 900,
      pixelWidth: 720,
      visibleHeight: 1280,
      devicePixelRatio: 1,
    );
    expect(phone.width, lessThanOrEqualTo(720));
    expect(phone.height, lessThanOrEqualTo(1280));
    expect(phone.width / phone.height, closeTo(720 / 1280, 0.001));

    final retina = fitOnboardingPhoto(
      maxWidth: 1400,
      maxHeight: 900,
      pixelWidth: 2000,
      visibleHeight: 1333,
      devicePixelRatio: 2,
    );
    expect(retina.width, lessThanOrEqualTo(1000));
    expect(retina.height, lessThanOrEqualTo(1333 / 2));
    expect(retina.width / retina.height, closeTo(2000 / 1333, 0.001));
  });

  testWidgets('desktop intro is a split page and the phone stays full bleed', (
    tester,
  ) async {
    await pumpScapeMatch(tester, showOnboarding: true);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final phonePhoto = tester.getSize(find.byType(ScapePhoto));
    expect(phonePhoto.width, closeTo(390, 1));
    expect(phonePhoto.height, closeTo(844, 1));
    expect(
      tester.getTopLeft(find.text(OnboardingMessages.findTitle)).dx,
      lessThan(40),
    );
    expect(
      tester.getTopLeft(find.text(OnboardingMessages.findTitle)).dy,
      greaterThan(390),
    );

    for (final size in const [Size(1280, 720), Size(1440, 900)]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScapeMatch(tester, showOnboarding: true);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      _expectDesktopIntro(tester, size);
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.byKey(AppKeys.onboardingNext));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size page $step');
      }
      expect(find.byKey(AppKeys.onboardingStart), findsOneWidget);
      expect(find.text(OnboardingMessages.payBody), findsOneWidget);
      final payPhoto = tester.getSize(find.byType(ScapePhoto));
      expect(payPhoto.width, lessThanOrEqualTo(720), reason: '$size');
      expect(payPhoto.height, lessThanOrEqualTo(1280), reason: '$size');
      expect(
        payPhoto.width / payPhoto.height,
        closeTo(720 / 1280, 0.02),
        reason: '$size',
      );
    }
  });

  testWidgets('Voltar sits beside Pular and returns only one page', (
    tester,
  ) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    expect(find.byKey(AppKeys.onboardingBack), findsNothing);
    expect(find.text(OnboardingMessages.back), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byKey(AppKeys.onboardingBack), findsNothing, reason: '$size');
      expect(find.byIcon(Icons.arrow_back), findsNothing, reason: '$size');
      expect(
        find.byKey(AppKeys.onboardingSkip),
        findsOneWidget,
        reason: '$size',
      );
      expect(
        find.byKey(AppKeys.onboardingNext),
        findsOneWidget,
        reason: '$size',
      );

      await tester.tap(find.byKey(AppKeys.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(OnboardingMessages.nearTitle), findsOneWidget);
      _expectBackBesideSkip(tester, size);

      await tester.tap(find.byKey(AppKeys.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(OnboardingMessages.inviteTitle), findsOneWidget);
      _expectBackBesideSkip(tester, size);

      await tester.tap(find.byKey(AppKeys.onboardingBack));
      await tester.pumpAndSettle();
      expect(find.text(OnboardingMessages.nearTitle), findsOneWidget);
      expect(find.text(OnboardingMessages.inviteTitle), findsNothing);
      expect(find.byKey(AppKeys.onboardingNext), findsOneWidget);

      await tester.tap(find.byKey(AppKeys.onboardingBack));
      await tester.pumpAndSettle();
      expect(find.text(OnboardingMessages.findTitle), findsOneWidget);
      expect(find.byKey(AppKeys.onboardingBack), findsNothing, reason: '$size');
      expect(find.text('←'), findsNothing, reason: '$size');
      expect(find.byKey(AppKeys.onboardingSkip), findsOneWidget);
      expect(find.byKey(AppKeys.onboardingNext), findsOneWidget);
    }
  });

  testWidgets('a retina desktop does not upscale the intro photo', (
    tester,
  ) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(3600, 2400);
    await tester.pumpAndSettle();
    expect(
      isScapeDesktop(tester.element(find.byType(OnboardingScreen))),
      isTrue,
    );
    final photo = tester.getSize(find.byType(ScapePhoto));
    expect(photo.width, greaterThan(500));
    expect(photo.width, lessThanOrEqualTo(1152 / 2 + 0.5));
    expect(photo.height, lessThanOrEqualTo(864 / 2 + 0.5));
    expect(photo.width / photo.height, closeTo(4 / 3, 0.02));
  });
}

void _expectBackBesideSkip(WidgetTester tester, Size size) {
  expect(find.byKey(AppKeys.onboardingBack), findsOneWidget, reason: '$size');
  expect(tester.widget(find.byKey(AppKeys.onboardingBack)), isA<TextButton>());
  expect(find.text(OnboardingMessages.back), findsOneWidget, reason: '$size');
  expect(find.text('←'), findsOneWidget, reason: '$size');
  expect(find.byIcon(Icons.arrow_back), findsNothing, reason: '$size');
  expect(tester.takeException(), isNull, reason: '$size');

  final skip = tester.getRect(find.byKey(AppKeys.onboardingSkip));
  final back = tester.getRect(find.byKey(AppKeys.onboardingBack));
  final next = tester.getRect(find.byKey(AppKeys.onboardingNext));
  expect(back.left, closeTo(skip.right, 1), reason: '$size');
  expect(
    (back.center.dy - skip.center.dy).abs(),
    lessThan(12),
    reason: '$size',
  );
  expect(back.top, greaterThan(size.height * 0.7), reason: '$size');
  expect(next.left, greaterThan(back.right), reason: '$size');
  expect(
    find.bySemanticsLabel(RegExp(r'Página \d de 4')),
    findsOneWidget,
    reason: '$size',
  );
}

void _expectDesktopIntro(WidgetTester tester, Size size) {
  final photo = tester.getSize(find.byType(ScapePhoto));
  expect(photo.width, lessThan(size.width * 0.7), reason: '$size');
  expect(photo.height, lessThan(size.height - 40), reason: '$size');
  expect(photo.width / photo.height, closeTo(4 / 3, 0.02), reason: '$size');
  final title = tester.getTopLeft(find.text(OnboardingMessages.findTitle));
  expect(title.dx, greaterThan(size.width * 0.5), reason: '$size');
  final skip = tester.getCenter(find.byKey(AppKeys.onboardingSkip));
  final next = tester.getCenter(find.byKey(AppKeys.onboardingNext));
  expect(skip.dx, greaterThan(size.width * 0.5), reason: '$size');
  expect(next.dx, greaterThan(skip.dx), reason: '$size');
  expect(next.dy, greaterThan(title.dy), reason: '$size');
}
