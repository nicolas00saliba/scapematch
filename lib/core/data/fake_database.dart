import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/groups/domain/group.dart';

/// In-memory store for the sample version of the app.
///
/// Cities, houses, rooms, and slots do not change. Groups do: joining or
/// creating a group updates [groups] for this session only. Nothing is sent
/// to a server. Closing the app forgets those changes.
class FakeDatabase {
  FakeDatabase({
    required List<City> cities,
    required List<EscapeHouse> houses,
    required List<EscapeRoom> rooms,
    required List<TimeSlot> slots,
    required List<Group> groups,
  }) : cities = List.unmodifiable(cities),
       houses = List.unmodifiable(houses),
       rooms = List.unmodifiable(rooms),
       slots = List.unmodifiable(slots),
       groups = List.of(groups);

  final List<City> cities;
  final List<EscapeHouse> houses;
  final List<EscapeRoom> rooms;
  final List<TimeSlot> slots;
  final List<Group> groups;

  int _sequence = 0;

  String nextGroupId() {
    _sequence += 1;
    return 'grp-local-$_sequence';
  }

  String nextParticipantId(String groupId) => 'local-$groupId-$_sequence';

  City? cityById(String id) => _find(cities, id, (city) => city.id);

  EscapeHouse? houseById(String id) => _find(houses, id, (house) => house.id);

  EscapeRoom? roomById(String id) => _find(rooms, id, (room) => room.id);

  TimeSlot? slotById(String id) => _find(slots, id, (slot) => slot.id);
}

T? _find<T>(List<T> items, String id, String Function(T item) idOf) {
  for (final item in items) {
    if (idOf(item) == id) {
      return item;
    }
  }
  return null;
}
