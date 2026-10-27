import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/domain/news_query.dart';

/// Feed fictício em memória.
///
/// [failList] existe para a tela de erro. O app deixa o valor falso. A
/// espera imita uma leitura curta, no mesmo espírito do repositório de grupos.
class FakeNewsRepository implements NewsRepository {
  FakeNewsRepository({
    required List<NewsItem> items,
    this.latency = const Duration(milliseconds: 280),
    this.failList = false,
  }) : _items = List<NewsItem>.unmodifiable(items);

  final List<NewsItem> _items;
  final Duration latency;
  final bool failList;

  @override
  Future<List<NewsItem>> list({
    required String? cityId,
    NewsCategory? category,
  }) async {
    await _pause();
    if (failList) {
      throw Exception('sample news list failed');
    }
    return filterNews(_items, cityId: cityId, category: category);
  }

  @override
  Future<NewsItem?> getById(String id) async {
    await _pause();
    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
