import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/providers/repositories.dart';

/// Categoria escolhida no feed. Nulo significa todas.
class NewsCategoryController extends Notifier<NewsCategory?> {
  @override
  NewsCategory? build() => null;

  void select(NewsCategory? category) {
    state = category;
  }
}

final newsCategoryProvider =
    NotifierProvider<NewsCategoryController, NewsCategory?>(
      NewsCategoryController.new,
    );

/// Feed da cidade selecionada, já filtrado pela categoria.
class NewsFeedViewModel extends AsyncNotifier<List<NewsItem>> {
  @override
  Future<List<NewsItem>> build() {
    final cityId = ref.watch(selectedCityIdProvider);
    final category = ref.watch(newsCategoryProvider);
    return ref
        .watch(newsRepositoryProvider)
        .list(cityId: cityId, category: category);
  }
}

final newsFeedViewModelProvider =
    AsyncNotifierProvider.autoDispose<NewsFeedViewModel, List<NewsItem>>(
      NewsFeedViewModel.new,
    );

/// Uma notícia aberta pelo id da rota.
class NewsDetailViewModel extends AsyncNotifier<NewsItem?> {
  NewsDetailViewModel(this.newsId);

  final String newsId;

  @override
  Future<NewsItem?> build() {
    return ref.watch(newsRepositoryProvider).getById(newsId);
  }
}

final newsDetailViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<NewsDetailViewModel, NewsItem?, String>(NewsDetailViewModel.new);
