import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';

/// One playable room. [capacity] is the room limit, not the group size.
class EscapeRoom {
  const EscapeRoom({
    required this.id,
    required this.houseId,
    required this.name,
    required this.theme,
    required this.category,
    required this.capacity,
    required this.durationMinutes,
    required this.difficulty,
    required this.priceCents,
    this.gameType = GameTypes.escapeRoom,
    this.minimumPlayers = 2,
    this.cancelWindow = const Duration(hours: 2),
  });

  final String id;
  final String houseId;
  final String name;
  final String theme;

  /// Carousel grouping. [theme] stays the short invented blurb.
  final RoomCategory category;

  /// Maximum number of players the room allows, including the creator.
  final int capacity;

  /// Mínimo para o grupo ficar pronto para reservar.
  final int minimumPlayers;

  /// Cancelar com esta antecedência, ou mais, devolve o pagamento simulado.
  final Duration cancelWindow;
  final int durationMinutes;
  final Difficulty difficulty;

  /// Fictional price per person, in cents. Nothing is charged.
  final int priceCents;

  /// Mesmo id de [GameTypes]. Uma sala antiga sem o campo conta como escape.
  final String gameType;
}
