import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/formatting/relative_time.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/news/data/fake_news_repository.dart';
import 'package:scapematch/features/news/data/sample_news.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/domain/news_query.dart';

import 'support/sample_clock.dart';

void main() {
  late List<NewsItem> items;
  late FakeNewsRepository repository;

  setUp(() {
    items = buildSampleNews(sampleNow);
    repository = FakeNewsRepository(items: items, latency: Duration.zero);
  });

  test('sample news keeps Curitiba stories for every game type', () {
    final curitiba = items.where((item) => item.cityId == SampleIds.curitiba);
    final elsewhere = items.where((item) => item.cityId != SampleIds.curitiba);
    expect(curitiba.length, 14);
    expect(
      curitiba.map((item) => item.gameType).toSet(),
      containsAll(const [
        GameTypes.escapeRoom,
        GameTypes.rpg,
        GameTypes.boardGame,
        GameTypes.laserTag,
        GameTypes.immersive,
      ]),
    );
    expect(elsewhere.length, greaterThanOrEqualTo(4));
    expect(
      items.map((item) => item.cityId).toSet(),
      containsAll(SampleIds.cities),
    );
    expect(
      items.singleWhere((item) => item.id == SampleNewsIds.cwbGrade).image,
      isNull,
    );
    final combo = items.singleWhere(
      (item) => item.id == SampleNewsIds.cwbCombo,
    );
    expect(combo.image, isNull);
    expect(combo.illustration, NewsIllustration.coffee);
  });

  test('filter keeps the city, the category, and newest first', () {
    final curitiba = filterNews(items, cityId: SampleIds.curitiba);
    expect(curitiba, hasLength(14));
    expect(curitiba.every((item) => item.cityId == SampleIds.curitiba), isTrue);
    expect(
      curitiba.first.publishedAt.isAfter(curitiba[1].publishedAt) ||
          curitiba.first.publishedAt.isAtSameMomentAs(curitiba[1].publishedAt),
      isTrue,
    );

    final promotions = filterNews(
      items,
      cityId: SampleIds.curitiba,
      category: NewsCategory.promotion,
    );
    expect(promotions, isNotEmpty);
    expect(
      promotions.every((item) => item.category == NewsCategory.promotion),
      isTrue,
    );
    expect(
      filterNews(
        items,
        cityId: SampleIds.portoAlegre,
        category: NewsCategory.promotion,
      ),
      isEmpty,
    );
    expect(filterNews(items, cityId: null), isEmpty);
    expect(filterNews(items, cityId: ''), isEmpty);
    expect(filterNews(items, cityId: 'cidade-que-nao-existe'), isEmpty);
  });

  test(
    'fake repository applies the same filter and can fail the list',
    () async {
      final fromRepo = await repository.list(
        cityId: SampleIds.curitiba,
        category: NewsCategory.promotion,
      );
      expect(
        fromRepo.map((item) => item.id),
        filterNews(
          items,
          cityId: SampleIds.curitiba,
          category: NewsCategory.promotion,
        ).map((item) => item.id),
      );

      final story = await repository.getById(SampleNewsIds.cwbBiblioteca);
      expect(story?.houseName, 'Portal do Batel');
      expect(story?.sourceKind, NewsSourceKind.website);
      expect(await repository.getById('nao-existe'), isNull);

      final failing = FakeNewsRepository(
        items: items,
        latency: Duration.zero,
        failList: true,
      );
      expect(
        () => failing.list(cityId: SampleIds.curitiba),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('relative time uses the injected clock', () {
    String label(Duration age) {
      return formatRelativeTime(
        publishedAt: sampleNow.subtract(age),
        now: sampleNow,
      );
    }

    expect(label(Duration.zero), 'agora');
    expect(label(const Duration(seconds: 30)), 'agora');
    expect(label(const Duration(minutes: 1)), 'há 1 min');
    expect(label(const Duration(minutes: 20)), 'há 20 min');
    expect(label(const Duration(minutes: 59)), 'há 59 min');
    expect(label(const Duration(hours: 1)), 'há 1 h');
    expect(label(const Duration(hours: 2)), 'há 2 h');
    expect(label(const Duration(hours: 23)), 'há 23 h');
    expect(label(const Duration(hours: 24)), 'há 1 dia');
    expect(label(const Duration(days: 4)), 'há 4 dias');
    expect(
      formatRelativeTime(
        publishedAt: sampleNow.add(const Duration(minutes: 5)),
        now: sampleNow,
      ),
      'agora',
    );
  });
}
