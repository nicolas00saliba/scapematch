import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('home sections follow primary, secondary, promos, tertiary', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
    expect(top(AppKeys.newsFeed), lessThan(top(AppKeys.roomCarousel('terror'))));
    expect(
      top(AppKeys.roomCarousel('terror')),
      lessThan(top(AppKeys.roomCarousel('mystery'))),
    );
    expect(
      top(AppKeys.roomCarousel('mystery')),
      lessThan(top(AppKeys.promoCarousel)),
    );
    expect(
      top(AppKeys.promoCarousel),
      lessThan(top(AppKeys.roomCarousel('adventure'))),
    );
    expect(
      top(AppKeys.roomCarousel('adventure')),
      lessThan(top(AppKeys.popularRooms)),
    );
    expect(find.text('Promoções'), findsNothing);
    expect(find.text('2 por 1 às quartas'), findsNothing);
    expect(find.byKey(AppKeys.promoDots), findsOneWidget);
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      findsNothing,
    );
  });

  testWidgets('arrows page every carousel kind and stop at the ends', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _page(tester, 'news');
    await _page(tester, 'terror');
    await _page(tester, 'promos');
    await _page(tester, 'popular');

    final promoScroll = find.descendant(
      of: find.byKey(AppKeys.promoCarousel),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    );
    for (var step = 0; step < 6; step++) {
      final next = find.byKey(AppKeys.carouselNext('promos'));
      if (next.evaluate().isEmpty) {
        break;
      }
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(AppKeys.carouselNext('promos')), findsNothing);
    expect(find.byKey(AppKeys.carouselPrevious('promos')), findsOneWidget);
    final end = tester.state<ScrollableState>(promoScroll).position;
    expect(end.pixels, greaterThan(0));
  });

  testWidgets('the first screen shows news and a slice of Terror', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(verticalScrollable);
    final viewportTop = tester.getTopLeft(verticalScrollable).dy;
    final viewportBottom =
        viewportTop + scrollable.position.viewportDimension;
    final news = tester.getRect(find.byKey(AppKeys.newsFeed));
    final terror = tester.getRect(find.byKey(AppKeys.roomCarousel('terror')));

    expect(news.bottom, lessThanOrEqualTo(viewportBottom + 1));
    expect(terror.top, lessThan(viewportBottom));
    expect(terror.bottom, greaterThan(viewportBottom));
    final visible = viewportBottom - terror.top;
    final fraction = visible / terror.height;
    expect(
      fraction,
      inInclusiveRange(0.22, 0.45),
      reason:
          'fraction=$fraction terror=${terror.height} news=${news.height} '
          'view=${viewportBottom - viewportTop} newsBottom=${news.bottom} '
          'viewBottom=$viewportBottom terrorTop=${terror.top}',
    );
  });

  testWidgets('home does not overflow at 360px and text scale 1.6', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.popularRooms),
      400,
      scrollable: verticalScrollable,
    );
    expect(tester.takeException(), isNull);
    final button = find.byKey(AppKeys.carouselNext('news'));
    if (button.evaluate().isNotEmpty) {
      expect(tester.getSize(button).height, greaterThanOrEqualTo(40));
    }
  });
}

Future<void> _page(WidgetTester tester, String id) async {
  final next = find.byKey(AppKeys.carouselNext(id));
  expect(find.byKey(AppKeys.carouselPrevious(id)), findsNothing);
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
  expect(find.byKey(AppKeys.carouselPrevious(id)), findsOneWidget);
  final previous = find.byKey(AppKeys.carouselPrevious(id));
  await tester.ensureVisible(previous);
  await tester.tap(previous);
  await tester.pumpAndSettle();
  expect(find.byKey(AppKeys.carouselPrevious(id)), findsNothing);
}
