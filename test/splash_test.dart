import 'dart:io';
import 'dart:math' as math;
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
  test('the splash logo appears, converges, spins, then reveals', () {
    final start = splashMotion(0, reduced: false);
    expect(start.logoOpacity, 0);
    expect(start.scale, SplashGate.enterScale);
    expect(start.absorb, 0);
    expect(start.turns, 0);
    expect(start.curtain, 1);
    expect(start.accent, 0);

    final held = splashMotion(SplashGate.holdEnd, reduced: false);
    expect(held.logoOpacity, 1);
    expect(held.scale, SplashGate.restScale);
    expect(held.absorb, 0);
    expect(held.turns, 0);
    expect(held.accent, 1);
    expect(held.curtain, 1);

    final burying = splashMotion(
      (SplashGate.holdEnd + SplashGate.buryEnd) / 2,
      reduced: false,
    );
    expect(burying.absorb, inExclusiveRange(0, 1));
    expect(burying.turns, 0);
    expect(burying.scale, SplashGate.restScale);
    expect(burying.curtain, 1);

    final buried = splashMotion(SplashGate.buryEnd, reduced: false);
    expect(buried.absorb, 1);
    expect(buried.accent, 0);
    expect(buried.turns, 0);
    expect(buried.scale, SplashGate.restScale);

    final approached = splashMotion(SplashGate.approachEnd, reduced: false);
    expect(approached.scale, SplashGate.approachScale);
    expect(approached.turns, SplashGate.approachTurns);
    expect(approached.turns, greaterThan(0));
    expect(approached.scale, lessThan(1.2));
    expect(approached.curtain, 1);

    final spinning = splashMotion(
      (SplashGate.approachEnd + SplashGate.spinEnd) / 2,
      reduced: false,
    );
    expect(spinning.scale, greaterThan(approached.scale));
    expect(spinning.turns, greaterThan(approached.turns));
    expect(spinning.curtain, 1);
    expect(spinning.logoOpacity, 1);

    final spun = splashMotion(SplashGate.spinEnd, reduced: false);
    expect(spun.scale, SplashGate.spinScale);
    expect(spun.turns, SplashGate.spinTurns);
    expect(spun.turns, greaterThan(1));
    expect(spun.logoOpacity, 1);
    expect(spun.curtain, 1);
    expect(spun.scale, greaterThan(spinning.scale));

    final gone = splashMotion(SplashGate.vanishEnd, reduced: false);
    expect(gone.logoOpacity, 0);
    expect(gone.scale, SplashGate.exitScale);
    expect(gone.scale, greaterThan(spun.scale));
    expect(gone.turns, SplashGate.exitTurns);
    expect(gone.curtain, 1);

    expect(splashMotion(1, reduced: false).curtain, 0);
    expect(splashMotion(1, reduced: false).logoOpacity, 0);

    final reducedStart = splashMotion(0, reduced: true);
    expect(reducedStart.logoOpacity, 1);
    expect(reducedStart.turns, 0);
    expect(reducedStart.absorb, 0);
    expect(reducedStart.scale, 1);
    expect(reducedStart.curtain, 1);
    expect(splashMotion(1, reduced: true).curtain, 0);
    expect(splashMotion(0.5, reduced: true).turns, 0);

    expect(SplashGate.duration.inMilliseconds, inInclusiveRange(1200, 1800));
    expect(SplashGate.reducedDuration.inMilliseconds, 180);
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
    expect(
      find.descendant(
        of: find.byKey(AppKeys.splash),
        matching: find.text('ScapeMatch'),
      ),
      findsOneWidget,
    );
    _expectPose(tester, 0, reduced: false);
    _expectBrandColors(tester);
    _expectColdStartCover(tester);

    var elapsed = 0;
    Future<void> pumpTo(double t) async {
      final target = (SplashGate.duration.inMilliseconds * t).round();
      await tester.pump(Duration(milliseconds: target - elapsed));
      elapsed = target;
    }

    await pumpTo(0.22);
    _expectPose(tester, elapsed / SplashGate.duration.inMilliseconds);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
    expect(_copperLineWidth(tester), SplashGate.accentWidth);
    await _saveSplashShot(tester, 'splash-1-logo.png');

    await pumpTo(0.46);
    _expectPose(tester, elapsed / SplashGate.duration.inMilliseconds);
    expect(_splashLogo(tester).wordmarkAbsorb, greaterThan(0.5));
    expect(_logoTurns(tester), 0);
    expect(_curtainOpacity(tester), 1);
    await _saveSplashShot(tester, 'splash-2-converge.png');

    await pumpTo(SplashGate.spinEnd);
    _expectPose(tester, elapsed / SplashGate.duration.inMilliseconds);
    expect(_logoScale(tester), closeTo(SplashGate.spinScale, 0.02));
    expect(_logoTurns(tester), closeTo(0.25, 0.02));
    expect(_curtainOpacity(tester), 1);
    expect(_logoOpacity(tester), 1);
    await _saveSplashShot(tester, 'splash-3-spin.png');

    await pumpTo((SplashGate.spinEnd + SplashGate.vanishEnd) / 2);
    _expectPose(tester, elapsed / SplashGate.duration.inMilliseconds);
    expect(_logoOpacity(tester), lessThan(1));
    expect(_curtainOpacity(tester), 1);

    await pumpTo(1);
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
    expect(_logoScale(tester), closeTo(1, 0.02));
    expect(_logoTurns(tester), 0);
    expect(_splashLogo(tester).wordmarkAbsorb, 0);
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
  final scale = tester.widget<Transform>(find.byKey(SplashGate.scaleKey));
  return scale.transform.storage[0];
}

double _logoTurns(WidgetTester tester) {
  final spin = tester.widget<Transform>(find.byKey(SplashGate.spinKey));
  final matrix = spin.transform.storage;
  final turns = math.atan2(matrix[1], matrix[0]) / (2 * math.pi);
  return turns < 0 ? turns + 1 : turns;
}

double _logoOpacity(WidgetTester tester) {
  return tester.widget<Opacity>(find.byKey(SplashGate.logoOpacityKey)).opacity;
}

double _curtainOpacity(WidgetTester tester) {
  return tester.widget<Opacity>(find.byKey(SplashGate.curtainKey)).opacity;
}

void _expectPose(WidgetTester tester, double t, {bool reduced = false}) {
  final motion = splashMotion(t, reduced: reduced);
  expect(_logoOpacity(tester), closeTo(motion.logoOpacity, 0.03));
  expect(_logoScale(tester), closeTo(motion.scale, 0.03));
  expect(_logoTurns(tester), closeTo(_wrappedTurns(motion.turns), 0.03));
  expect(_curtainOpacity(tester), closeTo(motion.curtain, 0.03));
  expect(_splashLogo(tester).wordmarkAbsorb, closeTo(motion.absorb, 0.03));
  expect(
    _copperLineWidth(tester),
    closeTo(SplashGate.accentWidth * motion.accent, 1.5),
  );
}

double _wrappedTurns(double turns) {
  final wrapped = turns % 1;
  return wrapped < 0 ? wrapped + 1 : wrapped;
}

void _expectColdStartCover(WidgetTester tester) {
  final home = tester.element(find.byType(HomeScreen));
  expect(
    home.findAncestorWidgetOfExactType<ExcludeSemantics>()?.excluding,
    isTrue,
  );
  expect(
    tester
        .element(find.byKey(AppKeys.splash))
        .findAncestorWidgetOfExactType<AbsorbPointer>(),
    isNotNull,
  );
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
