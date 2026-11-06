import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('a phone cold start shows the shared splash', (tester) async {
    await pumpParceiro(tester, size: const Size(390, 844), settle: false);
    expect(find.byKey(AppKeys.splash), findsOneWidget);
    final logo = tester.widget<ScapeLogo>(
      find.descendant(
        of: find.byKey(AppKeys.splash),
        matching: find.byType(ScapeLogo),
      ),
    );
    expect(logo.variant, ScapeLogoVariant.full);
    expect(logo.wordmarkAbsorb, 0);
    expect(logo.onDark, isFalse);

    await tester.pump(SplashGate.duration);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.splash), findsNothing);
  });

  testWidgets('the site width skips the splash', (tester) async {
    await pumpParceiro(tester, size: const Size(1280, 800), settle: false);
    expect(find.byKey(AppKeys.splash), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
