import 'package:scapematch/features/news/domain/news_item.dart';

/// Nome da categoria no chip, no selo e no detalhe.
String newsCategoryLabel(NewsCategory category) {
  return switch (category) {
    NewsCategory.newRoom => 'Novas salas',
    NewsCategory.schedule => 'Horários',
    NewsCategory.promotion => 'Promoções',
    NewsCategory.event => 'Eventos',
  };
}

/// Nome curto da origem, ao lado do "há 2 h".
String newsSourceLabel(NewsSourceKind kind) {
  return switch (kind) {
    NewsSourceKind.website => 'Site',
    NewsSourceKind.instagram => 'Instagram',
    NewsSourceKind.manual => 'Curadoria',
  };
}
