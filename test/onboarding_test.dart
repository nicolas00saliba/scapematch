import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
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

  testWidgets('Conta can replay the intro without an account', (tester) async {
    await pumpScapeMatch(
      tester,
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
    expect(photo.width, greaterThan(900));
    expect(photo.width, lessThanOrEqualTo(2000 / 2 + 0.5));
    expect(photo.height, lessThanOrEqualTo(1333 / 2 + 0.5));
    expect(photo.width / photo.height, closeTo(2000 / 1333, 0.02));
  });
}

void _expectDesktopIntro(WidgetTester tester, Size size) {
  final photo = tester.getSize(find.byType(ScapePhoto));
  expect(photo.width, lessThan(size.width * 0.7), reason: '$size');
  expect(photo.height, lessThan(size.height - 40), reason: '$size');
  expect(
    photo.width / photo.height,
    closeTo(2000 / 1333, 0.02),
    reason: '$size',
  );
  final title = tester.getTopLeft(find.text(OnboardingMessages.findTitle));
  expect(title.dx, greaterThan(size.width * 0.5), reason: '$size');
  final skip = tester.getCenter(find.byKey(AppKeys.onboardingSkip));
  final next = tester.getCenter(find.byKey(AppKeys.onboardingNext));
  expect(skip.dx, greaterThan(size.width * 0.5), reason: '$size');
  expect(next.dx, greaterThan(skip.dx), reason: '$size');
  expect(next.dy, greaterThan(title.dy), reason: '$size');
}
