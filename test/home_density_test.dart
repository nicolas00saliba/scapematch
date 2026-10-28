import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('home sections follow primary, secondary, promos, tertiary', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
    expect(
      top(AppKeys.newsFeed),
      lessThan(top(AppKeys.roomCarousel('terror'))),
    );
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
    final viewportBottom = viewportTop + scrollable.position.viewportDimension;
    final news = tester.getRect(find.byKey(AppKeys.newsFeed));
    final terror = tester.getRect(find.byKey(AppKeys.roomCarousel('terror')));

    expect(news.bottom, lessThanOrEqualTo(viewportBottom + 1));
    expect(terror.top, lessThan(viewportBottom));
    expect(terror.bottom, greaterThan(viewportBottom));
    final visible = viewportBottom - terror.top;
    final fraction = visible / terror.height;
    final roomTitle = find.descendant(
      of: find.byKey(AppKeys.roomCarousel('terror')),
      matching: find.text('O Sótão da Rua XV'),
    );
    expect(roomTitle, findsOneWidget);
    final titleTop = tester.getTopLeft(roomTitle).dy;
    expect(
      titleTop,
      lessThan(viewportBottom - 16),
      reason: 'a foto e o título do Terror precisam começar na primeira tela',
    );
    expect(
      fraction,
      inInclusiveRange(0.50, 0.60),
      reason:
          'fraction=$fraction terror=${terror.height} news=${news.height} '
          'view=${viewportBottom - viewportTop} newsBottom=${news.bottom} '
          'viewBottom=$viewportBottom terrorTop=${terror.top} '
          'titleTop=$titleTop',
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

  testWidgets('a two-line news title and its time stay inside the card', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    final context = tester.element(find.byKey(AppKeys.newsFeed));
    final reserved = newsCarouselCardHeight(context);
    final scaler = MediaQuery.textScalerOf(context);
    final theme = Theme.of(context);
    const contentWidth = newsCarouselCardWidth - 24;
    final titleStyle = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.2,
    );
    final oneTitle = _textHeight('Ag', titleStyle, scaler, contentWidth, 1);
    final whenLine = _textHeight(
      'há 30 min',
      theme.textTheme.bodySmall!,
      scaler,
      contentWidth,
      1,
    );
    final meta = _textHeight(
      'Portal do Batel',
      theme.textTheme.labelMedium!,
      scaler,
      contentWidth,
      1,
    );
    expect(
      reserved,
      greaterThanOrEqualTo(
        newsCarouselImageHeight +
            8 +
            meta +
            4 +
            (oneTitle * 2) +
            2 +
            whenLine +
            12,
      ),
    );

    final title = _twoLineTitle(titleStyle, scaler, contentWidth);
    final card = find.byKey(AppKeys.newsCard(title.id));
    await _scrollNews(tester, card);
    expect(tester.takeException(), isNull);

    final titleFinder = find.descendant(
      of: card,
      matching: find.text(title.text),
    );
    final titleWidget = tester.widget<Text>(titleFinder);
    final titleSize = tester.getSize(titleFinder);
    final titlePainter = TextPainter(
      text: TextSpan(text: title.text, style: titleWidget.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(tester.element(titleFinder)),
      maxLines: 2,
    )..layout(maxWidth: titleSize.width);
    expect(
      titlePainter.computeLineMetrics().length,
      2,
      reason:
          'o título de exemplo precisa ocupar duas linhas para o teste valer',
    );
    expect(titlePainter.didExceedMaxLines, isFalse);
    expect(titleSize.height, greaterThanOrEqualTo(titlePainter.height - 1));

    final cardRect = tester.getRect(card);
    final titleRect = tester.getRect(titleFinder);
    expect(titleRect.top, greaterThanOrEqualTo(cardRect.top - 0.5));
    expect(titleRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));

    final when = find.descendant(
      of: card,
      matching: find.textContaining('há '),
    );
    expect(when, findsOneWidget);
    final whenRect = tester.getRect(when);
    expect(whenRect.top, greaterThanOrEqualTo(titleRect.bottom - 0.5));
    expect(whenRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
    final whenPainter = TextPainter(
      text: TextSpan(
        text: tester.widget<Text>(when).data,
        style: tester.widget<Text>(when).style,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(tester.element(when)),
    )..layout();
    expect(
      tester.getSize(when).width,
      greaterThanOrEqualTo(whenPainter.width - 1),
    );
  });

  testWidgets('four promo flyers show the reachable dots before any tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    // Um pump aplica a largura. O seguinte é o pós-layout, quando a lista
    // ainda estima o extent e, sem a conta pelo conteúdo, pinta 5 pontos.
    await tester.pump();
    await tester.pump();

    expect(_promoDotCount(tester), 4);
    await tester.pumpAndSettle();
    expect(_promoDotCount(tester), promoFlyers.length);
    expect(_promoDotCount(tester), _reachablePromoStops(tester));
  });

  testWidgets(
    'promo dots match reachable pages and each arrow moves one flyer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScapeMatch(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(AppKeys.promoDots));
      expect(_activeDot(tester), 0);

      final scroll = _promoScroll(tester);
      final before = scroll.pixels;
      await _tapPromoNext(tester);
      final step = PromoCarousel.cardWidth + PromoCarousel.gap;
      expect(scroll.pixels - before, closeTo(step, 1));

      final carousel = tester.getRect(find.byKey(AppKeys.promoCarousel));
      final second = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.semanticLabel == '10% off no primeiro jogo',
      );
      expect(tester.getRect(second).left, closeTo(carousel.left, 2));

      var taps = 1;
      while (find.byKey(AppKeys.carouselNext('promos')).evaluate().isNotEmpty &&
          taps < 8) {
        await _tapPromoNext(tester);
        taps++;
      }
      expect(find.byKey(AppKeys.carouselNext('promos')), findsNothing);
      final dots = tester.widget<Row>(find.byKey(AppKeys.promoDots));
      expect(dots.children.length, taps + 1);
      expect(_activeDot(tester), dots.children.length - 1);
    },
  );

  testWidgets(
    'promo arrows and dots update when the screen or the font changes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScapeMatch(tester);
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();

      for (var step = 0; step < 8; step++) {
        final next = find.byKey(AppKeys.carouselNext('promos'));
        if (next.evaluate().isEmpty) {
          break;
        }
        await _tapPromoNext(tester);
      }
      expect(find.byKey(AppKeys.carouselNext('promos')), findsNothing);
      final atEnd = tester.widget<Row>(find.byKey(AppKeys.promoDots));
      expect(_activeDot(tester), atEnd.children.length - 1);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(AppKeys.carouselNext('promos')), findsOneWidget);
      final afterResize = tester.widget<Row>(find.byKey(AppKeys.promoDots));
      expect(_activeDot(tester), lessThan(afterResize.children.length - 1));

      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(AppKeys.carouselNext('promos')), findsOneWidget);
      expect(
        tester.widget<Row>(find.byKey(AppKeys.promoDots)).children,
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'the search hint fits at 390px and create becomes a compact button',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScapeMatch(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();

      final hint = find.text('Buscar sala ou casa');
      expect(hint, findsOneWidget);
      final hintWidget = tester.widget<Text>(hint);
      final hintPainter = TextPainter(
        text: TextSpan(text: hintWidget.data, style: hintWidget.style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(tester.element(hint)),
        maxLines: 1,
      )..layout();
      expect(
        tester.getSize(hint).width,
        greaterThanOrEqualTo(hintPainter.width - 1),
      );

      final fieldRect = tester.getRect(find.byKey(AppKeys.groupSearch));
      final createRect = tester.getRect(find.byKey(AppKeys.createGroup));
      final sameRow = (fieldRect.center.dy - createRect.center.dy).abs() < 12;
      if (sameRow) {
        expect(
          tester.widget(find.byKey(AppKeys.createGroup)),
          isA<IconButton>(),
        );
        expect(createRect.width, lessThanOrEqualTo(56));
      } else {
        expect(createRect.top, greaterThan(fieldRect.bottom - 1));
      }
      expect(createRect.height, greaterThanOrEqualTo(48));
      final semantics = tester.ensureSemantics();
      try {
        final node = tester.getSemantics(find.byKey(AppKeys.createGroup));
        expect(
          node.label == 'Criar grupo' || node.tooltip == 'Criar grupo',
          isTrue,
          reason: 'label=${node.label} tooltip=${node.tooltip}',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('the example-data notice is a small chip', (tester) async {
    await pumpScapeMatch(tester);
    final label = find.text('Dados de exemplo');
    expect(label, findsOneWidget);
    final chip = find
        .ancestor(of: label, matching: find.byType(Material))
        .first;
    final chipWidth = tester.getSize(chip).width;
    final rowWidth = tester.getSize(find.byKey(AppKeys.findGroup)).width;
    expect(chipWidth, lessThan(rowWidth * 0.7));
  });
}

Future<void> _scrollNews(WidgetTester tester, Finder card) async {
  await tester.scrollUntilVisible(
    card,
    280,
    scrollable: find.descendant(
      of: find.byKey(AppKeys.newsFeed),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    ),
  );
}

({String id, String text}) _twoLineTitle(
  TextStyle style,
  TextScaler scaler,
  double maxWidth,
) {
  final news = buildSampleNews(DateTime(2026, 10, 27, 12))
      .where((item) => item.cityId == SampleIds.curitiba);
  for (final item in news) {
    final painter = TextPainter(
      text: TextSpan(text: item.title, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    if (painter.computeLineMetrics().length == 2 &&
        !painter.didExceedMaxLines) {
      return (id: item.id, text: item.title);
    }
  }
  fail('nenhum título de Curitiba ocupa exatamente duas linhas');
}

double _textHeight(
  String text,
  TextStyle style,
  TextScaler scaler,
  double maxWidth,
  int maxLines,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

ScrollPosition _promoScroll(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byKey(AppKeys.promoCarousel),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  return tester.state<ScrollableState>(finder).position;
}

Future<void> _tapPromoNext(WidgetTester tester) async {
  final next = find.byKey(AppKeys.carouselNext('promos'));
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

int _promoDotCount(WidgetTester tester) {
  return tester.widget<Row>(find.byKey(AppKeys.promoDots)).children.length;
}

/// Paradas de um passo por flyer, com a largura que o carrossel realmente tem.
int _reachablePromoStops(WidgetTester tester) {
  final viewport = tester.getSize(find.byKey(AppKeys.promoCarousel)).width;
  const step = PromoCarousel.cardWidth + PromoCarousel.gap;
  final content =
      promoFlyers.length * PromoCarousel.cardWidth +
      (promoFlyers.length - 1) * PromoCarousel.gap;
  final maxScroll = content - viewport;
  var pages = 1;
  var offset = 0.0;
  while (offset < maxScroll - 1) {
    final next = offset + step;
    offset = next > maxScroll ? maxScroll : next;
    pages++;
  }
  return pages;
}

int _activeDot(WidgetTester tester) {
  final row = tester.widget<Row>(find.byKey(AppKeys.promoDots));
  var active = -1;
  for (var index = 0; index < row.children.length; index++) {
    final box = row.children[index] as Container;
    final color = (box.decoration! as BoxDecoration).color;
    if (color == AppColors.teal) {
      active = index;
    }
  }
  return active;
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
