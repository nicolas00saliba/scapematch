/// Tema da sala para os carrosséis da Home.
///
/// Não é a frase curta da sala (`EscapeRoom.theme`). É o agrupamento que
/// a pessoa vê: Terror, Mistério, e os outros.
enum RoomCategory {
  terror,
  mystery,
  adventure,
  scienceFiction,
  steampunk,
  egypt,
}

/// Ordem fixa dos carrosséis. Categoria sem sala na cidade some da Home.
const roomCategoryOrder = <RoomCategory>[
  RoomCategory.terror,
  RoomCategory.mystery,
  RoomCategory.adventure,
  RoomCategory.scienceFiction,
  RoomCategory.steampunk,
  RoomCategory.egypt,
];

RoomCategory? roomCategoryByName(String raw) {
  for (final category in RoomCategory.values) {
    if (category.name == raw) {
      return category;
    }
  }
  return null;
}
