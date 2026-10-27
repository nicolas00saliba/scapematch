import 'package:scapematch/features/news/domain/news_item.dart';

/// Filtra o feed pela cidade e, se houver, pela categoria.
///
/// Sem cidade (nulo ou vazio) a lista fica vazia, para ninguém listar o
/// país inteiro por engano. A Home não usa esse caminho: sem escolha salva
/// a cidade é Curitiba. A ordem é a mais recente primeiro. Empate de
/// horário desempata pelo id, para o teste não depender da ordem em que a
/// lista foi montada.
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
