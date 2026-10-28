import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('home order is groups, promos, news, then one room carousel', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
    expect(top(AppKeys.groupWindow), lessThan(top(AppKeys.promoCarousel)));
    expect(top(AppKeys.promoCarousel), lessThan(top(AppKeys.newsFeed)));
    expect(top(AppKeys.newsFeed), lessThan(top(AppKeys.roomsCarousel)));
    expect(find.text('Promoções'), findsOneWidget);
    expect(find.text('Novidades'), findsOneWidget);
    expect(find.text('Salas'), findsOneWidget);
    expect(find.text('Salas mais procuradas'), findsNothing);
    expect(find.byKey(AppKeys.roomCarousel('terror')), findsNothing);
    expect(find.text('2 por 1 às quartas'), findsNothing);
    expect(find.byKey(AppKeys.promoDots), findsOneWidget);
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      findsOneWidget,
    );
  });

  testWidgets('arrows page every carousel kind and stop at the ends', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _page(tester, 'news');
    await _page(tester, 'rooms');
    await _page(tester, 'promos');

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

  testWidgets('the first screen reaches the promo carousel', (tester) async {
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
    final groups = tester.getRect(find.byKey(AppKeys.groupWindow));
    final promos = tester.getRect(find.byKey(AppKeys.promoCarousel));

    expect(groups.top, greaterThanOrEqualTo(viewportTop - 1));
    expect(promos.top, greaterThan(groups.bottom - 1));
    expect(promos.top, lessThan(viewportBottom));
    final visible = (viewportBottom - promos.top).clamp(0.0, promos.height);
    expect(
      visible,
      greaterThan(80),
      reason:
          'visible=$visible promo=${promos.height} '
          'view=${viewportBottom - viewportTop}',
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
      find.byKey(AppKeys.roomsCarousel),
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
    final sampleCard = find
        .descendant(
          of: find.byKey(AppKeys.newsFeed),
          matching: find.byType(Card),
        )
        .first;
    final cardWidth = tester.getSize(sampleCard).width;
    final reserved = newsCarouselCardHeight(context, cardWidth);
    final scaler = MediaQuery.textScalerOf(context);
    final theme = Theme.of(context);
    final contentWidth = cardWidth - 24;
    final titleStyle = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.2,
    );
    final summaryStyle = theme.textTheme.bodyMedium!.copyWith(
      color: AppColors.muted,
      height: 1.35,
    );
    final oneTitle = _textHeight('Ag', titleStyle, scaler, contentWidth, 1);
    final oneSummary = _textHeight('Ag', summaryStyle, scaler, contentWidth, 1);
    final whenLine = _textHeight(
      'há 30 min · 27 out',
      theme.textTheme.bodySmall!,
      scaler,
      contentWidth,
      1,
    );
    final chip = _textHeight(
      'Jogos de tabuleiro',
      theme.textTheme.labelMedium!.copyWith(
        color: AppColors.teal,
        fontWeight: FontWeight.w800,
      ),
      scaler,
      contentWidth,
      1,
    );
    expect(
      reserved,
      greaterThanOrEqualTo(
        newsCarouselImageHeight +
            8 +
            chip +
            6 +
            8 +
            (oneTitle * 2) +
            4 +
            (oneSummary * 2) +
            4 +
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

    final story = buildSampleNews(DateTime(2026, 10, 27, 12))
        .singleWhere((item) => item.id == title.id);
    final summary = find.descendant(
      of: card,
      matching: find.text(story.summary),
    );
    expect(summary, findsOneWidget);
    final summaryRect = tester.getRect(summary);
    expect(summaryRect.top, greaterThanOrEqualTo(titleRect.bottom - 0.5));
    expect(summaryRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
    expect(
      find.descendant(
        of: card,
        matching: find.text(GameTypes.labelOf(story.gameType)),
      ),
      findsOneWidget,
    );

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
      final step = CarouselLayout.fit(
        viewport: scroll.viewportDimension,
        itemCount: promoFlyers.length,
        gap: PromoCarousel.gap,
        preferredItemWidth: PromoCarousel.preferredItemWidth,
      ).stride;
      expect(scroll.pixels - before, closeTo(step, 1.5));

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

  testWidgets('a touch drag past the group window scrolls the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    final windowScroll = tester.state<ScrollableState>(_groupWindowScroll);
    final page = tester.state<ScrollableState>(verticalScrollable).position;
    windowScroll.position.jumpTo(windowScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = page.pixels;

    final rect = tester.getRect(find.byKey(AppKeys.groupWindow));
    await tester.dragFrom(
      rect.center,
      const Offset(0, -180),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    expect(page.pixels, greaterThan(before + 40));
    expect(
      windowScroll.position.pixels,
      closeTo(windowScroll.position.maxScrollExtent, 1),
    );
  });

  testWidgets('city and game type fit side by side at 390px', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    final city = tester.getRect(find.byKey(AppKeys.citySelector));
    final game = tester.getRect(find.byKey(AppKeys.gameTypeSelector));
    expect((city.center.dy - game.center.dy).abs(), lessThan(8));
    expect(city.right, lessThanOrEqualTo(game.left));
    expect(tester.takeException(), isNull);

    final longestCity = _widestCity(tester);
    for (final cityId in [SampleIds.curitiba, longestCity]) {
      await _selectCity(tester, cityId);
      for (final choice in GameTypes.choices) {
        await tester.tap(find.byKey(AppKeys.gameTypeSelector));
        await tester.pumpAndSettle();
        expect(find.text(choice.label), findsWidgets);
        await tester.tap(find.byKey(AppKeys.gameTypeOption(choice.id)));
        await tester.pumpAndSettle();
        _expectClosedGameLabelFits(tester, choice.shortLabel);
      }
    }
  });

  testWidgets('the group window scrolls almost-full groups and obeys filters', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    final scrollable = find.descendant(
      of: find.byKey(AppKeys.groupWindow),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(1),
    );
    expect(
      tester.getSize(find.byKey(AppKeys.groupWindow)).height,
      closeTo(groupWindowMaxHeight, 1),
    );
    expect(
      tester
          .widget<Scrollbar>(
            find.descendant(
              of: find.byKey(AppKeys.groupWindow),
              matching: find.byType(Scrollbar),
            ),
          )
          .thumbVisibility,
      isTrue,
    );

    await tester.tap(find.byKey(AppKeys.gameTypeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.groupCard('grp-cwb-porao-rpg')), findsOneWidget);
    expect(find.text('Mesa de RPG no porão'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.groupWindow),
        matching: find.text('O Porão sem Luz'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      findsNothing,
    );
    final cardHeight = tester
        .getSize(find.byKey(AppKeys.groupCard('grp-cwb-porao-rpg')))
        .height;
    expect(
      tester.getSize(find.byKey(AppKeys.groupWindow)).height,
      closeTo(cardHeight, 2),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      lessThanOrEqualTo(1),
    );
    expect(
      tester
          .widget<Scrollbar>(
            find.descendant(
              of: find.byKey(AppKeys.groupWindow),
              matching: find.byType(Scrollbar),
            ),
          )
          .thumbVisibility,
      isFalse,
    );
  });

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

  testWidgets('the game type filters news and the single room carousel', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await tester.tap(find.byKey(AppKeys.gameTypeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mesa longa do Batel'),
      400,
      scrollable: verticalScrollable,
    );
    expect(find.text('Mesa longa do Batel'), findsOneWidget);
    expect(find.text('O Cofre do Café'), findsNothing);
    expect(find.text('Clube de tabuleiro da XV'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Mesa nova: o porão abre campanha às quintas'),
      400,
      scrollable: verticalScrollable,
    );
    expect(
      find.text('Mesa nova: o porão abre campanha às quintas'),
      findsOneWidget,
    );
    expect(find.text('Sala nova: A Biblioteca Proibida'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.newsFeed),
        matching: find.text('RPG'),
      ),
      findsWidgets,
    );
  });
}

Future<void> _scrollNews(WidgetTester tester, Finder card) async {
  final scrollable = find.descendant(
    of: find.byKey(AppKeys.newsFeed),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  for (var step = 0; step < 24; step++) {
    if (_fullyInView(tester, card, scrollable)) {
      return;
    }
    final next = find.byKey(AppKeys.carouselNext('news'));
    if (next.evaluate().isEmpty) {
      break;
    }
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
  expect(_fullyInView(tester, card, scrollable), isTrue);
}

bool _fullyInView(WidgetTester tester, Finder target, Finder view) {
  if (target.evaluate().isEmpty || view.evaluate().isEmpty) {
    return false;
  }
  final rect = tester.getRect(target);
  final bounds = tester.getRect(view);
  return rect.left >= bounds.left - 1 && rect.right <= bounds.right + 1;
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

String _widestCity(WidgetTester tester) {
  const names = <String, String>{
    SampleIds.curitiba: 'Curitiba',
    SampleIds.saoPaulo: 'São Paulo',
    SampleIds.rioDeJaneiro: 'Rio de Janeiro',
    SampleIds.beloHorizonte: 'Belo Horizonte',
    SampleIds.portoAlegre: 'Porto Alegre',
  };
  final sample = tester.widget<Text>(
    find.descendant(
      of: find.byKey(AppKeys.citySelector),
      matching: find.text('Curitiba'),
    ),
  );
  var widest = SampleIds.curitiba;
  var widestWidth = 0.0;
  for (final entry in names.entries) {
    final painter = TextPainter(
      text: TextSpan(text: entry.value, style: sample.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(
        tester.element(find.byKey(AppKeys.citySelector)),
      ),
      maxLines: 1,
    )..layout();
    if (painter.width > widestWidth) {
      widestWidth = painter.width;
      widest = entry.key;
    }
  }
  return widest;
}

void _expectClosedGameLabelFits(WidgetTester tester, String label) {
  final finder = find.descendant(
    of: find.byKey(AppKeys.gameTypeSelector),
    matching: find.text(label),
  );
  expect(finder, findsOneWidget, reason: label);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$label está cortado no seletor fechado',
  );
  final painter = TextPainter(
    text: TextSpan(text: label, style: paragraph.text.style),
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: 1,
  )..layout(maxWidth: paragraph.size.width);
  expect(painter.didExceedMaxLines, isFalse, reason: label);
  expect(painter.width, lessThanOrEqualTo(paragraph.size.width + 0.5));
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.ensureVisible(find.byKey(AppKeys.citySelector));
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

final Finder _groupWindowScroll = find.descendant(
  of: find.byKey(AppKeys.groupWindow),
  matching: find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axis == Axis.vertical,
  ),
);

int _promoDotCount(WidgetTester tester) {
  return tester.widget<Row>(find.byKey(AppKeys.promoDots)).children.length;
}

/// Paradas de um passo por flyer, com a largura que o carrossel realmente tem.
int _reachablePromoStops(WidgetTester tester) {
  final viewport = _promoScroll(tester).viewportDimension;
  return CarouselLayout.fit(
    viewport: viewport,
    itemCount: promoFlyers.length,
    gap: PromoCarousel.gap,
    preferredItemWidth: PromoCarousel.preferredItemWidth,
  ).stops;
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
