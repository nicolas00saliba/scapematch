import 'package:scapematch/features/news/domain/news_item.dart';

/// Lê o feed de novidades.
///
/// A tela depende desta interface, não da lista fictícia. Uma implementação
/// de Supabase, ou uma curadoria, entra no lugar da falsa sem mudar o feed.
abstract class NewsRepository {
  /// [cityId] nulo ou vazio devolve lista vazia. A Home sempre manda uma
  /// cidade. [category] nula não filtra.
  Future<List<NewsItem>> list({
    required String? cityId,
    NewsCategory? category,
  });

  Future<NewsItem?> getById(String id);
}
