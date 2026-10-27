import 'package:scapematch/features/news/domain/news_item.dart';

/// Filtra o feed pela cidade e, se houver, pela categoria.
///
/// Sem cidade a lista fica vazia: o app não assume Curitiba. A ordem é a
/// mais recente primeiro. Empate de horário desempata pelo id, para o teste
/// não depender da ordem em que a lista foi montada.
List<NewsItem> filterNews(
  List<NewsItem> items, {
  required String? cityId,
  NewsCategory? category,
}) {
  if (cityId == null || cityId.isEmpty) {
    return const [];
  }
  final filtered =
      [
        for (final item in items)
          if (item.cityId == cityId &&
              (category == null || item.category == category))
            item,
      ]..sort((a, b) {
        final byDate = b.publishedAt.compareTo(a.publishedAt);
        if (byDate != 0) {
          return byDate;
        }
        return a.id.compareTo(b.id);
      });
  return List.unmodifiable(filtered);
}
