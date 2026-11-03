import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/groups/domain/group.dart';

/// In-memory store for the sample version of the app.
///
/// Cities and houses do not change. Groups change when someone joins.
/// Rooms and slots change when the house edits price or opens a time,
/// in this session only. Nothing is sent to a server. Closing the app
/// forgets those changes.
class FakeDatabase {
  FakeDatabase({
    required List<City> cities,
    required List<EscapeHouse> houses,
    required List<EscapeRoom> rooms,
    required List<TimeSlot> slots,
    required List<Group> groups,
  }) : cities = List.unmodifiable(cities),
       houses = List.unmodifiable(houses),
       rooms = List.of(rooms),
       slots = List.of(slots),
       groups = List.of(groups);

  final List<City> cities;
  final List<EscapeHouse> houses;
  final List<EscapeRoom> rooms;
  final List<TimeSlot> slots;
  final List<Group> groups;

  /// Group ids and participant ids have their own counters.
  ///
  /// A participant id used to reuse the group counter, and that counter
  /// moved only when a group was created. Joining a group then produced
  /// the same suffix forever (`...-0`) until somebody created a group.
  int _groupSequence = 0;
  int _participantSequence = 0;

  String nextGroupId() {
    final taken = groups.map((group) => group.id).toSet();
    while (true) {
      _groupSequence += 1;
      final id = 'grp-local-$_groupSequence';
      if (!taken.contains(id)) {
        return id;
      }
    }
  }

  /// A new membership id. Increments even when no group is being created,
  /// and skips any id already stored on a participant.
  String nextParticipantId() {
    final taken = <String>{
      for (final group in groups)
        for (final person in group.participants) person.id,
    };
    while (true) {
      _participantSequence += 1;
      final id = 'ptc-local-$_participantSequence';
      if (!taken.contains(id)) {
        return id;
      }
    }
  }

  City? cityById(String id) => _find(cities, id, (city) => city.id);

  EscapeHouse? houseById(String id) => _find(houses, id, (house) => house.id);

  EscapeRoom? roomById(String id) => _find(rooms, id, (room) => room.id);

  TimeSlot? slotById(String id) => _find(slots, id, (slot) => slot.id);

  void addRoom(EscapeRoom room) {
    rooms.add(room);
  }

  void replaceRoom(EscapeRoom room) {
    final index = rooms.indexWhere((item) => item.id == room.id);
    if (index < 0) {
      throw StateError('Sala não encontrada.');
    }
    rooms[index] = room;
  }

  TimeSlot addSlot({required String roomId, required DateTime startsAt}) {
    final slot = TimeSlot(
      id: 'slot-local-${slots.length + 1}',
      roomId: roomId,
      startsAt: startsAt,
    );
    slots.add(slot);
    return slot;
  }
}

T? _find<T>(List<T> items, String id, String Function(T item) idOf) {
  for (final item in items) {
    if (idOf(item) == id) {
      return item;
    }
  }
  return null;
}
