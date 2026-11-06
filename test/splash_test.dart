import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_app.dart';

void main() {
  test('the splash motion fades in, holds, then reveals the next screen', () {
    expect(splashLogoEnter(0, reduced: false), 0);
    expect(splashLogoScale(0), 0.9);
    expect(splashCurtainOpacity(0, reduced: false), 1);
    expect(splashLogoEnter(SplashGate.enterEnd, reduced: false), 1);
    expect(splashCurtainOpacity(SplashGate.exitStart, reduced: false), 1);
    expect(splashCurtainOpacity(1, reduced: false), 0);
    expect(splashLogoEnter(0, reduced: true), 1);
    expect(splashCurtainOpacity(0, reduced: true), 1);
    expect(splashCurtainOpacity(1, reduced: true), 0);
    expect(SplashGate.duration.inMilliseconds, inInclusiveRange(1200, 1800));
    expect(SplashGate.reducedDuration.inMilliseconds, lessThan(250));
    expect(SplashGate.background, const Color(0xFF0F4C4A));
    expect(SplashGate.copper, const Color(0xFF9A4F24));
  });

  testWidgets('a phone cold start covers the home with the existing logo', (
    tester,
  ) async {
    if (Directory('/opt/cursor/artifacts').existsSync()) {
      await tester.runAsync(_loadPoppins);
    }
    await pumpScapeMatch(tester, viewport: const Size(390, 844), settle: false);

    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(_splashLogo(tester).variant, ScapeLogoVariant.full);
    expect(_splashLogo(tester).onDark, isTrue);
    expect(_curtainOpacity(tester), 1);
    expect(_logoOpacity(tester), 0);
    expect(_logoScale(tester), closeTo(0.9, 0.02));
    _expectBrandColors(tester);

    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_logoOpacity(tester), 1);
    expect(_logoScale(tester), closeTo(1, 0.02));
    expect(_curtainOpacity(tester), 1);
    expect(_copperLineWidth(tester), 72);
    await _saveSplashShot(tester, 'splash-mobile.png');

    await tester.pump(const Duration(milliseconds: 650));
    expect(_curtainOpacity(tester), lessThan(1));
    expect(_logoOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('ScapeMatch'), findsNothing);
  });

  testWidgets(
    'reloading shows the splash again; navigation and resume do not',
    (tester) async {
      await pumpScapeMatch(
        tester,
        viewport: const Size(390, 844),
        settle: false,
      );
      expect(find.byKey(AppKeys.splash), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScapeMatch(tester, viewport: const Size(390, 844));
      expect(find.byKey(AppKeys.splash), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byKey(AppKeys.accountTab));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.byKey(AppKeys.splash), findsNothing);

      GoRouter.of(tester.element(find.byType(AccountScreen))).go('/');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(AppKeys.splash), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AppKeys.splash), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets('a route change during the splash does not restart it', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      viewport: const Size(390, 844),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(_logoScale(tester), closeTo(1, 0.02));

    GoRouter.of(tester.element(find.byType(OnboardingScreen)))
        .go('/convite/${SampleIds.groupCwbCofreAlmost}');
    await tester.pump();
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_logoScale(tester), closeTo(1, 0.05));

    await tester.pump(SplashGate.duration);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.text('Convite'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('the first real opening plays the splash and then the intro', (
    tester,
  ) async {
    final store = OnboardingStore(seen: false);
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      viewport: const Size(390, 844),
      settle: false,
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
    );

    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(store.seen, isFalse);

    await tester.pump(SplashGate.duration);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(store.seen, isFalse);
  });

  testWidgets('a later real opening skips the intro after the splash', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      onboardingMode: AppMode.real,
      viewport: const Size(390, 844),
    );

    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('the site width never shows the splash, even on first visit', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      viewport: const Size(960, 800),
      settle: false,
      overrides: [
        onboardingStoreProvider.overrideWithValue(OnboardingStore(seen: false)),
      ],
    );
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.pump(SplashGate.duration);
    expect(find.byKey(AppKeys.splash), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScapeMatch(
      tester,
      viewport: const Size(1280, 800),
      settle: false,
    );
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(AppKeys.splash), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('just under the site width still shows the splash', (
    tester,
  ) async {
    await pumpScapeMatch(tester, viewport: const Size(959, 800), settle: false);
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
  });

  testWidgets(
    'growing into the site hides the splash and shrinking does not start it',
    (tester) async {
      await pumpScapeMatch(
        tester,
        viewport: const Size(390, 844),
        settle: false,
      );
      expect(find.byKey(AppKeys.splash), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      expect(find.byKey(AppKeys.splash), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScapeMatch(
        tester,
        viewport: const Size(1280, 800),
        settle: false,
      );
      expect(find.byKey(AppKeys.splash), findsNothing);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AppKeys.splash), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets('reduced motion keeps a short fade', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpScapeMatch(tester, viewport: const Size(390, 844), settle: false);
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_logoOpacity(tester), 1);
    expect(_curtainOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_curtainOpacity(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a narrow phone with large text does not overflow the splash', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScapeMatch(tester, viewport: const Size(320, 568), settle: false);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    expect(_splashLogo(tester).variant, ScapeLogoVariant.full);
    final splash = tester.getRect(find.byKey(AppKeys.splash));
    final logo = tester.getRect(
      find.descendant(
        of: find.byKey(AppKeys.splash),
        matching: find.byType(ScapeLogo),
      ),
    );
    expect(logo.left, greaterThanOrEqualTo(splash.left));
    expect(logo.right, lessThanOrEqualTo(splash.right));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the splash does not write a seen flag', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpScapeMatch(tester, viewport: const Size(390, 844));
    expect(prefs.getKeys().where((key) => key.contains('splash')), isEmpty);
    expect(prefs.getBool(OnboardingStore.storageKey), isNull);
  });
}

ScapeLogo _splashLogo(WidgetTester tester) {
  return tester.widget<ScapeLogo>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(ScapeLogo),
    ),
  );
}

double _logoScale(WidgetTester tester) {
  final scale = tester.widget<Transform>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(Transform),
    ),
  );
  return scale.transform.storage[0];
}

double _logoOpacity(WidgetTester tester) {
  final marks = tester.widgetList<Opacity>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(Opacity),
    ),
  );
  return marks.last.opacity;
}

double _curtainOpacity(WidgetTester tester) {
  final marks = tester.widgetList<Opacity>(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byType(Opacity),
    ),
  );
  return marks.first.opacity;
}

double _copperLineWidth(WidgetTester tester) {
  final copper = find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == SplashGate.copper,
  );
  final line = tester.widget<SizedBox>(
    find.descendant(of: copper, matching: find.byType(SizedBox)),
  );
  return line.width!;
}

void _expectBrandColors(WidgetTester tester) {
  expect(
    find.descendant(
      of: find.byKey(AppKeys.splash),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == SplashGate.background,
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == SplashGate.copper,
    ),
    findsOneWidget,
  );
}

Future<void> _loadPoppins() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
  await loader.load();
}

Future<void> _saveSplashShot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) {
    return;
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>());
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}
