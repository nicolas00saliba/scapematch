import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';

/// Houses, rooms, and time slots.
///
/// Kept separate from groups so a future version can fill this catalog
/// from an ExperienceSource per house without touching the group screens.
/// That source is a file, a partner feed, or an integration the house
/// allows. It is not a scraper of a live website. See docs/DADOS_REAIS.md.
abstract class CatalogRepository {
  Future<List<EscapeHouse>> listHousesByCity(String cityId);
  Future<List<EscapeRoom>> listRoomsByHouse(String houseId);
  Future<List<TimeSlot>> listSlotsByRoom(String roomId);
}
