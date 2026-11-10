import 'package:scapematch/core/supabase/row_values.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/feature_order.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Colunas da vitrine. Documento, telefone e renda não entram.
const venueVitrineColumns =
    'id, city_id, name, neighborhood, street_address, address_number, '
    'postal_code, latitude, longitude, category, badge, status, created_at, '
    'receives_payments, featured_rank';

const roomColumns =
    'id, venue_id, name, theme, category, game_type, capacity, '
    'minimum_players, duration_minutes, difficulty, price_cents, '
    'cancel_window_minutes, accent, featured_rank';

const sessionColumns = 'id, room_id, starts_at, availability, cancelled_at';

/// Casas aprovadas, salas e sessões. A casa de exemplo só aparece se o
/// seed da EscapeMatch Demo estiver no banco.
class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<EscapeHouse>> listHousesByCity(String cityId) async {
    final snap = await _load();
    final houses = [
      for (final house in snap.houses.values)
        if (house.cityId == cityId) house,
    ]..sort((a, b) => compareFeatured(a.featuredRank, b.featuredRank, a.name, b.name));
    return houses;
  }

  @override
  Future<List<EscapeRoom>> listRoomsByHouse(String houseId) async {
    final snap = await _load();
    final rooms = [
      for (final room in snap.rooms.values)
        if (room.houseId == houseId) room,
    ]..sort((a, b) => compareFeatured(a.featuredRank, b.featuredRank, a.name, b.name));
    return rooms;
  }

  @override
  Future<List<TimeSlot>> listSlotsByRoom(String roomId) async {
    final snap = await _load();
    final slots = [
      for (final slot in snap.slots)
        if (slot.roomId == roomId) slot,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return slots;
  }

  @override
  Future<List<RoomListing>> listRoomsByCity(String cityId) async {
    final snap = await _load();
    final listings = [
      for (final room in snap.rooms.values)
        if (snap.houses[room.houseId]?.cityId == cityId) snap.listing(room.id)!,
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
    final snap = await _load();
    return snap.listing(roomId);
  }

  Future<_CatalogSnap> _load() async {
    final cities = await _client
        .from('cities')
        .select('id, name, state_code, state_name');
    final venues = await _client
        .from('venues_vitrine')
        .select(venueVitrineColumns)
        .eq('status', 'approved');
    final openVenues = [
      for (final row in venues)
        if (venueReceivesGroups(row)) row,
    ];
    final venueIds = <String>{
      for (final row in openVenues) row['id'] as String,
    };
    final rooms = venueIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _client
              .from('rooms')
              .select(roomColumns)
              .inFilter('venue_id', venueIds.toList());
    final roomIds = <String>{for (final row in rooms) row['id'] as String};
    final sessions = roomIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _client
              .from('room_sessions')
              .select(sessionColumns)
              .inFilter('room_id', roomIds.toList())
              .isFilter('cancelled_at', null);
    return _CatalogSnap(
      cities: {for (final row in cities) row['id'] as String: cityFromRow(row)},
      houses: {
        for (final row in openVenues) row['id'] as String: houseFromRow(row),
      },
      rooms: {for (final row in rooms) row['id'] as String: roomFromRow(row)},
      slots: [
        for (final row in sessions)
          if (row['starts_at'] != null)
            TimeSlot(
              id: row['id'] as String,
              roomId: row['room_id'] as String,
              startsAt: dateTimeOf(row['starts_at'])!,
            ),
      ],
    );
  }
}

class _CatalogSnap {
  _CatalogSnap({
    required this.cities,
    required this.houses,
    required this.rooms,
    required this.slots,
  });

  final Map<String, City> cities;
  final Map<String, EscapeHouse> houses;
  final Map<String, EscapeRoom> rooms;
  final List<TimeSlot> slots;

  RoomListing? listing(String roomId) {
    final room = rooms[roomId];
    if (room == null) return null;
    final house = houses[room.houseId];
    if (house == null) return null;
    final city = cities[house.cityId];
    return RoomListing(
      room: room,
      houseId: house.id,
      houseName: house.name,
      cityId: house.cityId,
      cityName: city?.name ?? house.cityId,
      houseFeaturedRank: house.featuredRank,
    );
  }
}

City cityFromRow(Map<String, dynamic> row) {
  return City(
    id: row['id'] as String,
    name: textOf(row['name']),
    stateCode: textOf(row['state_code']),
    stateName: textOf(row['state_name']),
  );
}

EscapeHouse houseFromRow(Map<String, dynamic> row) {
  return EscapeHouse(
    id: row['id'] as String,
    cityId: textOf(row['city_id']),
    name: textOf(row['name']),
    neighborhood: textOf(row['neighborhood']),
    latitude: doubleOf(row['latitude']),
    longitude: doubleOf(row['longitude']),
    streetAddress: streetLine(
      street: textOf(row['street_address']),
      number: textOf(row['address_number']),
    ),
    receivesPayments: venueReceivesGroups(row),
    featuredRank: optionalRank(row['featured_rank']),
  );
}

EscapeRoom roomFromRow(Map<String, dynamic> row) {
  return EscapeRoom(
    id: row['id'] as String,
    houseId: textOf(row['venue_id']),
    name: textOf(row['name']),
    theme: textOf(row['theme']),
    category:
        roomCategoryByName(textOf(row['category'])) ?? RoomCategory.mystery,
    capacity: intOf(row['capacity'], fallback: 2),
    minimumPlayers: intOf(row['minimum_players'], fallback: 2),
    durationMinutes: intOf(row['duration_minutes'], fallback: 60),
    difficulty: difficultyOf(textOf(row['difficulty'])),
    priceCents: intOf(row['price_cents']),
    gameType: textOf(row['game_type']).isEmpty
        ? 'escape-room'
        : textOf(row['game_type']),
    cancelWindow: Duration(
      minutes: intOf(row['cancel_window_minutes'], fallback: 120),
    ),
    accent: intOf(row['accent']),
    featuredRank: optionalRank(row['featured_rank']),
  );
}

Difficulty difficultyOf(String raw) {
  return switch (raw) {
    'easy' => Difficulty.easy,
    'hard' => Difficulty.hard,
    _ => Difficulty.medium,
  };
}
