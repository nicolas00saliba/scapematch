import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
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
    expect(
      find.text('Escolha a cidade acima para ver as novidades.'),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );

    await _selectCity(tester, SampleIds.curitiba);

    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsNothing);
    expect(find.textContaining('há 2 h'), findsWidgets);
    expect(find.text('Ilustração fictícia'), findsOneWidget);

    await tester.tap(
      find.byKey(AppKeys.newsCategory(NewsCategory.promotion.name)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbOperaPromo)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbCombo)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppKeys.newsCategoryAll));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsOneWidget,
    );

    await _selectCity(tester, SampleIds.saoPaulo);
    expect(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      findsNothing,
    );
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spLinha)), findsOneWidget);
    expect(find.byKey(AppKeys.newsCard(SampleNewsIds.spPromo)), findsOneWidget);
  });

  testWidgets('a category with no stories in the city shows the empty feed', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(
      find.byKey(AppKeys.newsCategory(NewsCategory.promotion.name)),
    );
    await tester.pumpAndSettle();

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
    await pumpScapeMatch(
      tester,
      overrides: [
        newsRepositoryProvider.overrideWithValue(_HangingNewsRepository()),
      ],
    );

    await tester.tap(find.byKey(AppKeys.citySelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.beloHorizonte)));
    // The spinner keeps scheduling frames, so this cannot use pumpAndSettle.
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
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)),
      400,
      scrollable: verticalScrollable,
    );
    await tester.tap(find.byKey(AppKeys.newsCard(SampleNewsIds.cwbBiblioteca)));
    await tester.pumpAndSettle();

    expect(find.text('Novidade'), findsOneWidget);
    expect(find.text('Sala nova: A Biblioteca Proibida'), findsOneWidget);
    expect(find.textContaining('Link de origem (fictício)'), findsOneWidget);
    expect(
      find.textContaining('exemplo.scapematch.invalid/batel/biblioteca'),
      findsOneWidget,
    );
    expect(find.textContaining('há 2 h'), findsWidgets);
  });
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
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
