import 'package:scapematch/features/catalog/domain/room_category.dart';

/// Nome do carrossel. A foto de cada tema fica em [roomCategoryImage].
String roomCategoryLabel(RoomCategory category) {
  return switch (category) {
    RoomCategory.terror => 'Terror',
    RoomCategory.mystery => 'Mistério',
    RoomCategory.adventure => 'Aventura',
    RoomCategory.scienceFiction => 'Sci-fi',
    RoomCategory.steampunk => 'Steampunk',
    RoomCategory.egypt => 'Egito',
  };
}

/// Foto fictícia do tema. Aventura é arquivo novo; o resto reaproveita
/// as figuras já usadas no feed.
String roomCategoryImage(RoomCategory category) {
  return switch (category) {
    RoomCategory.terror => 'assets/images/news/terror.jpg',
    RoomCategory.mystery => 'assets/images/news/biblioteca.jpg',
    RoomCategory.adventure => 'assets/images/rooms/aventura.jpg',
    RoomCategory.scienceFiction => 'assets/images/news/scifi.jpg',
    RoomCategory.steampunk => 'assets/images/news/steampunk.jpg',
    RoomCategory.egypt => 'assets/images/news/egito.jpg',
  };
}
