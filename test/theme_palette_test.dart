import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';

import 'support/pump_app.dart';

void main() {
  test('Noite de Mistério text pairs meet WCAG AA', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      final scheme = theme.colorScheme;
      final status = theme.extension<ScapeStatusColors>()!;
      final page = theme.scaffoldBackgroundColor;
      final pairs = <(Color, Color)>[
        (scheme.onSurface, page),
        (scheme.onSurface, scheme.surface),
        (scheme.onSurface, scheme.surfaceContainerHigh),
        (scheme.onSurfaceVariant, page),
        (scheme.onSurfaceVariant, scheme.surface),
        (scheme.onPrimary, scheme.primary),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onTertiary, scheme.tertiary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (scheme.onSecondaryContainer, scheme.secondaryContainer),
        (scheme.onTertiaryContainer, scheme.tertiaryContainer),
        (scheme.primary, page),
        (scheme.secondary, page),
        (scheme.error, scheme.surface),
        (scheme.onError, scheme.error),
        (status.success, page),
        (status.onSuccess, status.success),
        (status.onSuccessContainer, status.successContainer),
        (status.alert, page),
        (status.onAlert, status.alert),
        (status.onAlertContainer, status.alertContainer),
      ];
      for (final (ink, ground) in pairs) {
        expect(
          _contrast(ink, ground),
          greaterThanOrEqualTo(4.5),
          reason:
              '$brightness ${ink.toARGB32().toRadixString(16)} on '
              '${ground.toARGB32().toRadixString(16)}',
        );
      }
    }
  });

  testWidgets('home and the intro render in the dark theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpScapeMatch(
      tester,
      showOnboarding: true,
      overrides: [
        onboardingStoreProvider.overrideWithValue(OnboardingStore(seen: false)),
      ],
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(AppKeys.onboardingSkip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Quase cheios'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color ink, Color ground) {
  final lighter = math.max(ink.computeLuminance(), ground.computeLuminance());
  final darker = math.min(ink.computeLuminance(), ground.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}
