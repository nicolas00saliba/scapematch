import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('promos and news drag with the mouse and with a finger', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final kind in const [
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
      ]) {
        await pumpScapeMatch(tester);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpAndSettle();
        for (final id in const ['promos', 'news']) {
          await tester.scrollUntilVisible(
            find.byKey(AppKeys.carouselFrame(id)),
            400,
            scrollable: verticalScrollable,
          );
          await tester.pumpAndSettle();
          final scrollable = find.descendant(
            of: find.byKey(AppKeys.carouselFrame(id)),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable && widget.axis == Axis.horizontal,
            ),
          );
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(0);
          await tester.pumpAndSettle();
          final before = position.pixels;
          await tester.drag(
            scrollable,
            Offset(-position.viewportDimension * 0.7, 0),
            kind: kind,
          );
          await tester.pumpAndSettle();
          expect(
            position.pixels,
            greaterThan(before + 8),
            reason: '$id ${size.width} $kind',
          );
        }
      }
    }
  });

  testWidgets('the home carousels do not arm a timer in widget tests', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(AppKeys.promoCarousel),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable && widget.axis == Axis.horizontal,
            ),
          ),
        )
        .position;
    await tester.pump(const Duration(seconds: 6));
    expect(position.pixels, 0);
  });

  testWidgets('auto advance walks forward, pauses on hover, then disposes', (
    tester,
  ) async {
    ArrowCarousel.debugAllowAutoAdvanceInTests = true;
    addTearDown(() => ArrowCarousel.debugAllowAutoAdvanceInTests = false);

    await tester.pumpWidget(_demoCarousel());
    await tester.pump();
    final position = _demoOffset(tester);
    expect(position.pixels, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(
      tester.getCenter(find.byKey(AppKeys.carouselFrame('demo'))),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, 0);

    await gesture.moveTo(const Offset(-20, -20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(8));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'a finger press pauses auto advance and dispose drops the timer',
    (tester) async {
      ArrowCarousel.debugAllowAutoAdvanceInTests = true;
      addTearDown(() => ArrowCarousel.debugAllowAutoAdvanceInTests = false);

      await tester.pumpWidget(_demoCarousel());
      await tester.pump();
      final position = _demoOffset(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(AppKeys.carouselFrame('demo'))),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(position.pixels, 0);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(8));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Widget _demoCarousel() {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          height: 120,
          child: ArrowCarousel(
            id: 'demo',
            height: 80,
            itemCount: 4,
            loop: true,
            autoAdvance: true,
            itemBuilder: (context, index) => Text('item-$index'),
          ),
        ),
      ),
    ),
  );
}

ScrollPosition _demoOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(AppKeys.carouselFrame('demo')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
        ),
      )
      .position;
}
