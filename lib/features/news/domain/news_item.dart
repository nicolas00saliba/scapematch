/// Categoria do feed. Os nomes na tela ficam em `news_labels.dart`.
enum NewsCategory { newRoom, schedule, promotion, event }

/// De onde a notícia diz que veio. Ainda não há coleta de verdade.
enum NewsSourceKind { website, instagram, manual }

/// Uma novidade de escape room, pronta para a tela desenhar.
///
/// O nome da casa e o da cidade já vêm copiados, no mesmo espírito do grupo.
/// A tela não junta tabelas. Uma fonte real preenche o mesmo objeto.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.houseName,
    required this.cityId,
    required this.cityName,
    required this.publishedAt,
    required this.sourceKind,
    this.image,
    this.sourceUrl,
  });

  final String id;
  final String title;
  final String summary;
  final NewsCategory category;
  final String houseName;
  final String cityId;
  final String cityName;

  /// Caminho de asset (`assets/...`) ou URL `http(s)`. Vazio gera uma
  /// ilustração no código. A tela trata os dois formatos.
  final String? image;

  final DateTime publishedAt;

  /// Endereço de origem, quando a fonte tiver um. Pode ser fictício.
  final String? sourceUrl;

  final NewsSourceKind sourceKind;
}
