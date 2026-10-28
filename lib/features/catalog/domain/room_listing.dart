import 'package:scapematch/features/catalog/domain/escape_room.dart';

/// Sala pronta para um cartão: a sala, a casa e a cidade já juntas.
class RoomListing {
  const RoomListing({
    required this.room,
    required this.houseId,
    required this.houseName,
    required this.cityId,
    required this.cityName,
  });

  final EscapeRoom room;
  final String houseId;
  final String houseName;
  final String cityId;
  final String cityName;
}
