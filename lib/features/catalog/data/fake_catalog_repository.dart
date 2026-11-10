import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/feature_order.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
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
          ..sort(
            (a, b) =>
                compareFeatured(a.featuredRank, b.featuredRank, a.name, b.name),
          );
    return houses;
  }

  @override
  Future<List<EscapeRoom>> listRoomsByHouse(String houseId) async {
    await _pause();
    final rooms =
        _database.rooms.where((room) => room.houseId == houseId).toList()
          ..sort(
            (a, b) =>
                compareFeatured(a.featuredRank, b.featuredRank, a.name, b.name),
          );
    return rooms;
  }

  @override
  Future<List<TimeSlot>> listSlotsByRoom(String roomId) async {
    await _pause();
    final slots =
        _database.slots
            .where((slot) => slot.roomId == roomId && slot.active)
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return slots;
  }

  @override
  Future<List<RoomListing>> listRoomsByCity(String cityId) async {
    await _pause();
    final listings = <RoomListing>[
      for (final house in _database.houses)
        if (house.cityId == cityId)
          for (final room in _database.rooms)
            if (room.houseId == house.id) _listing(room, house),
    ]..sort(
      (a, b) => compareFeatured(
        a.room.featuredRank,
        b.room.featuredRank,
        a.room.name,
        b.room.name,
      ),
    );
    return listings;
  }

  @override
  Future<RoomListing?> findRoom(String roomId) async {
    await _pause();
    for (final room in _database.rooms) {
      if (room.id != roomId) {
        continue;
      }
      for (final house in _database.houses) {
        if (house.id == room.houseId) {
          return _listing(room, house);
        }
      }
    }
    return null;
  }

  /// Grava o preço por pessoa nesta sessão. A ficha da sala lê o mesmo objeto.
  Future<void> updatePrice(String roomId, int priceCents) async {
    await _pause();
    final room = _database.roomById(roomId);
    if (room == null) {
      throw StateError('Sala não encontrada.');
    }
    _database.replaceRoom(room.copyWith(priceCents: priceCents));
  }

  /// Abre um horário nesta sessão. Criar grupo passa a oferecer esse horário.
  Future<TimeSlot> addSlot(String roomId, DateTime startsAt) async {
    await _pause();
    if (_database.roomById(roomId) == null) {
      throw StateError('Sala não encontrada.');
    }
    return _database.addSlot(roomId: roomId, startsAt: startsAt);
  }

  RoomListing _listing(EscapeRoom room, EscapeHouse house) {
    var cityName = '';
    for (final city in _database.cities) {
      if (city.id == house.cityId) {
        cityName = city.name;
        break;
      }
    }
    return RoomListing(
      room: room,
      houseId: house.id,
      houseName: house.name,
      cityId: house.cityId,
      cityName: cityName,
      houseFeaturedRank: house.featuredRank,
    );
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
