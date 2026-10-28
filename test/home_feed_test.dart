import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/scapematch_app.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/cities/data/selected_city_store.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/news/presentation/news_browse_screen.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/domain/news_query.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets(
    'opening Home with no saved city shows Curitiba groups and feed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScapeMatch(
        tester,
        overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
      );

      expect(find.text('Escolha uma cidade'), findsNothing);
      expect(
        find.text('Escolha a cidade acima para ver os grupos.'),
        findsNothing,
      );
      expect(
        find.text('Escolha a cidade acima para ver as novidades.'),
        findsNothing,
      );
      expect(find.text('Curitiba'), findsWidgets);
      expect(
        find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
        findsOneWidget,
      );
      await revealCarouselItem(
        tester,
        'rooms',
        find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
      );
      expect(
        find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
        findsWidgets,
      );
      await tester.enterText(find.byKey(AppKeys.groupSearch), 'Cofre');
      await tester.pumpAndSettle();
      expect(
        find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
        300,
        scrollable: find.descendant(
          of: find.byKey(AppKeys.newsFeed),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
        ),
      );
      expect(
        find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
        findsWidgets,
      );
      expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsNothing);
    },
  );

  testWidgets('a saved city wins over the Curitiba default', (tester) async {
    SharedPreferences.setMockInitialValues({
      SelectedCityStore.storageKey: SampleIds.saoPaulo,
    });
    final store = SelectedCityStore();
    await store.load();

    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        selectedCityStoreProvider.overrideWithValue(store),
      ],
    );

    expect(find.text('São Paulo'), findsWidgets);
    expect(find.text('Curitiba'), findsNothing);
    await revealCarouselItem(
      tester,
      'rooms',
      find.byKey(AppKeys.roomCard(SampleIds.roomSpMetro)),
    );
    expect(find.byKey(AppKeys.roomCard(SampleIds.roomSpMetro)), findsWidgets);
    expect(find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)), findsNothing);
    await revealCarouselItem(
      tester,
      'news',
      find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)),
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsOneWidget);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
  });

  testWidgets('choosing a city is what the next open reads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );

    await _selectCity(tester, SampleIds.rioDeJaneiro);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SelectedCityStore.storageKey),
      SampleIds.rioDeJaneiro,
    );

    final restored = SelectedCityStore();
    await restored.load();
    // Outro ProviderScope no mesmo lugar não pode mudar a quantidade de
    // overrides. A árvore sai antes da “próxima abertura”.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        selectedCityStoreProvider.overrideWithValue(restored),
      ],
    );

    expect(find.text('Rio de Janeiro'), findsWidgets);
    expect(find.text('O Apartamento da Avenida'), findsWidgets);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
  });

  testWidgets('the feed sits below the search and follows city and category', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );

    expect(
      tester.getTopLeft(find.byKey(AppKeys.newsFeed)).dy,
      greaterThan(tester.getTopLeft(find.byKey(AppKeys.groupSearch)).dy),
    );
    await _scrollNews(tester, AppKeys.newsCard(SampleNewsIds.cwbBiblioteca));
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsWidgets,
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsNothing);
    expect(find.textContaining('há 2 h'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.semanticLabel == 'Sala nova: A Biblioteca Proibida',
      ),
      findsWidgets,
    );

    await _openNewsBrowse(tester);
    expect(find.text('Ilustração fictícia'), findsNWidgets(2));
    await _tapNewsChip(
      tester,
      AppKeys.newsCategory(NewsCategory.promotion.name),
    );

    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca))),
      findsNothing,
    );
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbOperaPromo))),
      findsOneWidget,
    );
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbCombo))),
      findsOneWidget,
    );

    await _tapNewsChip(tester, AppKeys.newsCategoryAll);
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca))),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _selectCity(tester, SampleIds.saoPaulo);
    await _scrollNews(tester, AppKeys.newsCard(SampleNewsIds.spLinha));
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsWidgets);
    await revealCarouselItem(
      tester,
      'news',
      find.byKey(AppKeys.newsCard(SampleNewsIds.spPromo)),
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spPromo)), findsWidgets);
  });

  testWidgets('a category with no stories in the city shows the empty feed', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _selectCity(tester, SampleIds.portoAlegre);
    await _openNewsBrowse(tester);
    await _tapNewsChip(
      tester,
      AppKeys.newsCategory(NewsCategory.promotion.name),
    );

    expect(
      find.textContaining('Nenhuma novidade de promoções em Porto Alegre.'),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.poaEvento)), findsNothing);
  });

  testWidgets('the feed shows an error with retry', (tester) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        newsRepositoryProvider.overrideWithValue(
          FakeNewsRepository(
            items: buildSampleNews(sampleNow),
            latency: Duration.zero,
            failList: true,
          ),
        ),
      ],
    );

    await _selectCity(tester, SampleIds.curitiba);
    expect(
      find.text('Não foi possível carregar as novidades.'),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.newsRetry), findsOneWidget);
  });

  testWidgets('the feed shows a loading state until the repository answers', (
    tester,
  ) async {
    // A cidade já vem escolhida, então a primeira carga é loading.
    // skipLoadingOnReload esconde o spinner numa troca de cidade.
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          newsRepositoryProvider.overrideWithValue(_HangingNewsRepository()),
          selectedCityIdProvider.overrideWithBuild(
            (ref, notifier) => SampleIds.beloHorizonte,
          ),
        ],
        child: const ScapeMatchApp(),
      ),
    );
    // O spinner agenda frames para sempre. Sem pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Carregando novidades...'), findsOneWidget);
  });

  testWidgets('tapping a card opens the story', (tester) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );
    await _selectCity(tester, SampleIds.curitiba);
    await _scrollNews(tester, AppKeys.newsCard(SampleNewsIds.cwbBiblioteca));
    final card = find
        .byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca))
        .first;
    final rect = tester.getRect(card);
    await tester.tapAt(Offset(rect.left + 24, rect.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Novidade'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byKey(AppKeys.newsBackHome), findsNothing);
    expect(find.text('Sala nova: A Biblioteca Proibida'), findsOneWidget);
    expect(find.textContaining('Link de origem (fictício)'), findsOneWidget);
    expect(
      find.textContaining('exemplo.scapematch.invalid/batel/biblioteca'),
      findsOneWidget,
    );
    expect(find.textContaining('há 2 h'), findsWidgets);
  });

  testWidgets('a direct news link without a stack can go back home', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        newsRepositoryProvider.overrideWithValue(
          FakeNewsRepository(
            items: buildSampleNews(sampleNow),
            latency: Duration.zero,
          ),
        ),
      ],
    );

    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .go('/news/${SampleNewsIds.cwbBiblioteca}');
    await tester.pumpAndSettle();

    expect(find.text('Sala nova: A Biblioteca Proibida'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(AppKeys.newsBackHome), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.newsBackHome));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(AppKeys.newsFeed), findsOneWidget);
  });

  testWidgets('an unknown news link explains that the story is missing', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        newsRepositoryProvider.overrideWithValue(
          FakeNewsRepository(
            items: buildSampleNews(sampleNow),
            latency: Duration.zero,
          ),
        ),
      ],
    );

    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .go('/news/id-inexistente');
    await tester.pumpAndSettle();

    expect(find.text('Novidade não encontrada'), findsOneWidget);
    expect(
      find.text('Esse link não aponta para uma notícia de exemplo.'),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.newsBackHome), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.newsBackHome));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Curitiba on a small phone with large text does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const ProviderScope(retry: noAutomaticRetry, child: ScapeMatchApp()),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(HomeScreen)))
          .scale(10),
      closeTo(13, 0.01),
    );

    await _selectCity(tester, SampleIds.curitiba);
    // Em 320px a busca fica na linha de baixo e o centro da faixa horizontal
    // cai na barra. O salto no controller monta o cartão sem depender do toque.
    final newsScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(AppKeys.newsFeed),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
    );
    final card = find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca));
    while (card.evaluate().isEmpty &&
        newsScroll.position.pixels < newsScroll.position.maxScrollExtent) {
      newsScroll.position.jumpTo(
        (newsScroll.position.pixels + 300).clamp(
          0.0,
          newsScroll.position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsWidgets,
    );
  });

  testWidgets('changing the news chip or city does not flash the spinner', (
    tester,
  ) async {
    final repository = _PausableNewsRepository(buildSampleNews(sampleNow));
    await pumpScapeMatch(
      tester,
      overrides: [
        newsRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
      ],
    );
    await _selectCity(tester, SampleIds.curitiba);
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      300,
      scrollable: find.descendant(
        of: find.byKey(AppKeys.newsFeed),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
    );
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsWidgets,
    );

    await _openNewsBrowse(tester);
    final promotions = find.byKey(
      AppKeys.newsCategory(NewsCategory.promotion.name),
    );
    await tester.ensureVisible(promotions);
    await tester.pumpAndSettle();
    repository.pause = Completer<void>();
    await tester.tap(promotions);
    await tester.pump();

    expect(find.text('Carregando novidades...'), findsNothing);
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca))),
      findsOneWidget,
    );

    repository.pause!.complete();
    await tester.pumpAndSettle();
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca))),
      findsNothing,
    );
    expect(
      _inNewsBrowse(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbCombo))),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _scrollNews(tester, AppKeys.newsCard(SampleNewsIds.cwbBiblioteca));
    await tester.ensureVisible(find.byKey(AppKeys.citySelector));
    await tester.pumpAndSettle();
    repository.pause = Completer<void>();
    await tester.tap(find.byKey(AppKeys.citySelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
    await tester.pump();

    expect(find.text('Carregando novidades...'), findsNothing);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsWidgets,
    );

    repository.pause!.complete();
    await tester.pumpAndSettle();
    await _scrollNews(tester, AppKeys.newsCard(SampleNewsIds.spLinha));
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsWidgets);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
  });

  testWidgets('recreating Home clears the group search', (tester) async {
    await pumpScapeMatch(tester);
    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Metrô');
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsNothing,
    );

    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/groups/new');
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(CreateGroupScreen))).go('/');
    await tester.pumpAndSettle();
    // A lista da cidade espera o repositório. Sem animação, pumpAndSettle
    // pode encerrar antes.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(AppKeys.groupSearch))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsOneWidget,
    );
  });
}

Future<void> _scrollNews(WidgetTester tester, Key card) async {
  await tester.scrollUntilVisible(
    find.byKey(card),
    280,
    scrollable: find.descendant(
      of: find.byKey(AppKeys.newsFeed),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    ),
  );
}

Future<void> _openNewsBrowse(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(AppKeys.newsSeeAll));
  await tester.tap(find.byKey(AppKeys.newsSeeAll));
  await tester.pumpAndSettle();
  expect(find.byType(NewsBrowseScreen), findsOneWidget);
}

Finder _inNewsBrowse(Finder finder) {
  return find.descendant(of: find.byType(NewsBrowseScreen), matching: finder);
}

Future<void> _tapNewsChip(WidgetTester tester, Key key) async {
  final chip = find.byKey(key);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.ensureVisible(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

class _PausableNewsRepository implements NewsRepository {
  _PausableNewsRepository(this.items);

  final List<NewsItem> items;
  Completer<void>? pause;

  @override
  Future<NewsItem?> getById(String id) async {
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<List<NewsItem>> list({
    required String? cityId,
    NewsCategory? category,
  }) async {
    final pause = this.pause;
    if (pause != null) {
      await pause.future;
    }
    return filterNews(items, cityId: cityId, category: category);
  }
}

class _HangingNewsRepository implements NewsRepository {
  @override
  Future<NewsItem?> getById(String id) => Future<NewsItem?>.value();

  @override
  Future<List<NewsItem>> list({
    required String? cityId,
    NewsCategory? category,
  }) {
    if (cityId == null) {
      return Future<List<NewsItem>>.value(const []);
    }
    return Completer<List<NewsItem>>().future;
  }
}
