import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets(
    'the phone header uses the mark and the wide header the full logo',
    (tester) async {
      await pumpScapeMatch(tester);
      expect(find.byType(ScapeLogo), findsOneWidget);
      expect(find.text('ScapeMatch'), findsNothing);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();

      expect(find.text('ScapeMatch'), findsOneWidget);
      final logo = tester.widget<ScapeLogo>(find.byType(ScapeLogo));
      expect(logo.variant, ScapeLogoVariant.full);
    },
  );

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

  testWidgets('wordmarkAbsorb holds the lockup, then trains into the pin', (
    tester,
  ) async {
    Future<void> pump(double absorb) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScapeLogo(
                height: 80,
                onDark: false,
                wordmarkAbsorb: absorb,
              ),
            ),
          ),
        ),
      );
    }

    Rect pinInLogo() {
      final origin = tester.getTopLeft(find.byType(ScapeLogo));
      return tester.getRect(find.byType(SvgPicture)).shift(-origin);
    }

    await pump(0);
    final pin = tester.getRect(find.byType(SvgPicture));
    final word = tester.getRect(find.text('ScapeMatch'));
    final box = tester.getRect(find.byType(ScapeLogo));
    expect(
      pin.width / pin.height,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.01),
    );
    expect(word.left, greaterThanOrEqualTo(pin.right - 1));
    expect(word.left, greaterThanOrEqualTo(box.left));
    expect(word.right, lessThanOrEqualTo(box.right));
    expect(pin.top, greaterThanOrEqualTo(box.top));
    expect(pin.bottom, lessThanOrEqualTo(box.bottom + 0.5));
    expect(
      find.descendant(
        of: find.byType(ScapeLogo),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
    );
    final held = pinInLogo();

    await pump(0.5);
    final movedPin = pinInLogo();
    final movedWord = tester.getRect(find.text('ScapeMatch'));
    expect(movedPin.width, closeTo(held.width, 0.5));
    expect(movedPin.height, closeTo(held.height, 0.5));
    expect(movedPin.left, closeTo(held.left, 0.5));
    expect(movedWord.left, lessThan(word.left));
    final clip = tester.getRect(
      find.descendant(
        of: find.byType(ScapeLogo),
        matching: find.byType(ClipRect),
      ),
    );
    expect(
      clip.left,
      closeTo(tester.getRect(find.byType(SvgPicture)).right, 1),
    );
    expect(movedWord.right, lessThanOrEqualTo(clip.right + 1));

    await pump(1);
    expect(find.text('ScapeMatch'), findsNothing);
    final buried = tester.getRect(find.byType(SvgPicture));
    expect(
      buried.width / buried.height,
      closeTo(ScapeLogo.markAspectWidth / ScapeLogo.markAspectHeight, 0.01),
    );
    expect(buried.width, closeTo(pin.width, 0.5));
    expect(pinInLogo().left, closeTo(held.left, 0.5));
  });
}
