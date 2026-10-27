import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';

class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository(
    this._database, {
    this.latency = const Duration(milliseconds: 280),
  });

  final FakeDatabase _database;
  final Duration latency;

  @override
  Future<List<EscapeHouse>> listHousesByCity(String cityId) async {
    await _pause();
    final houses =
        _database.houses.where((house) => house.cityId == cityId).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return houses;
  }

  @override
  Future<List<EscapeRoom>> listRoomsByHouse(String houseId) async {
    await _pause();
    final rooms =
        _database.rooms.where((room) => room.houseId == houseId).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return rooms;
  }

  @override
  Future<List<TimeSlot>> listSlotsByRoom(String roomId) async {
    await _pause();
    final slots =
        _database.slots.where((slot) => slot.roomId == roomId).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return slots;
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
