import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';

/// Houses, rooms, and time slots.
///
/// Kept separate from groups so a future version can fill this catalog
/// from venue websites without touching the group screens.
abstract class CatalogRepository {
  Future<List<EscapeHouse>> listHousesByCity(String cityId);
  Future<List<EscapeRoom>> listRoomsByHouse(String houseId);
  Future<List<TimeSlot>> listSlotsByRoom(String roomId);
}
