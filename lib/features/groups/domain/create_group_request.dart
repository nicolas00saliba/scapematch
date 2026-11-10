import 'package:scapematch/features/groups/domain/party_companion.dart';

class CreateGroupRequest {
  const CreateGroupRequest({
    required this.cityId,
    required this.houseId,
    required this.roomId,
    required this.slotId,
    required this.extraSpots,
    this.minimumPlayers,
    required this.creatorUserId,
    required this.creatorDisplayName,
    this.companions = const [],
  });

  final String cityId;
  final String houseId;
  final String roomId;
  final String slotId;

  /// Vagas além de quem cria. O máximo do grupo é 1 + [extraSpots].
  final int extraSpots;

  /// Mínimo do host, contando quem cria. Nulo significa faixa exata no máximo.
  final int? minimumPlayers;

  /// Account id of the person creating the group. Comes from the current user.
  final String creatorUserId;

  /// Name shown on the creator's seat. Not hardcoded by the repository.
  final String creatorDisplayName;

  /// Amigos que já sentam com quem cria. As vagas de [extraSpots] incluem
  /// essas pessoas e ainda precisam sobrar ao menos uma para desconhecidos.
  final List<PartyCompanion> companions;
}
