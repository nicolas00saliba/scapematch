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

/// Tag compartilhada pelo cartão e pela capa da sala, para o voo Hero.
String roomHeroTag(String roomId) => 'room-cover-$roomId';

/// Tema da capa, quando a foto é a de um carrossel. Nulo se a capa for outra.
RoomCategory? categoryForCover(String cover) {
  for (final category in RoomCategory.values) {
    if (roomCategoryImage(category) == cover) {
      return category;
    }
  }
  return null;
}

/// Capa do tema e mais duas fotos da galeria. Tudo local, sem hotlink.
List<String> roomGallery(RoomCategory category) {
  final extra = switch (category) {
    RoomCategory.terror => 'assets/images/rooms/gallery/terror.jpg',
    RoomCategory.mystery => 'assets/images/rooms/gallery/misterio.jpg',
    RoomCategory.adventure => 'assets/images/rooms/gallery/aventura.jpg',
    RoomCategory.scienceFiction => 'assets/images/rooms/gallery/scifi.jpg',
    RoomCategory.steampunk => 'assets/images/rooms/gallery/steampunk.jpg',
    RoomCategory.egypt => 'assets/images/rooms/gallery/egito.jpg',
  };
  return [
    roomCategoryImage(category),
    extra,
    'assets/images/rooms/gallery/amigos.jpg',
  ];
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
