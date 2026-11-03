import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the phone header uses the mark and the wide header the full logo', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    expect(find.byType(ScapeLogo), findsOneWidget);
    expect(find.text('ScapeMatch'), findsNothing);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    expect(find.text('ScapeMatch'), findsOneWidget);
    final logo = tester.widget<ScapeLogo>(find.byType(ScapeLogo));
    expect(logo.variant, ScapeLogoVariant.full);
  });

  testWidgets('the intro shows the full logo', (tester) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('ScapeMatch'), findsWidgets);
    expect(
      tester
          .widgetList<ScapeLogo>(find.byType(ScapeLogo))
          .every((logo) => logo.variant == ScapeLogoVariant.full),
      isTrue,
    );
  });
}
