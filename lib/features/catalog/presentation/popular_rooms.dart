import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';

/// Ordem fictícia de procura. Não é uma medição: é um ranking de exemplo.
const popularRoomRank = <String>[
  SampleIds.roomCwbCofre,
  'room-cwb-opera',
  SampleIds.roomSpMetro,
  'room-rj-apartamento',
  'room-cwb-sotao',
  SampleIds.roomPoaEstufa,
  'room-sp-cobertura',
  'room-bh-bar',
  'room-cwb-nave',
  'room-rj-bond',
];

List<RoomListing> rankPopularRooms(List<RoomListing> rooms) {
  final ranked = [...rooms];
  ranked.sort((a, b) {
    final aRank = popularRoomRank.indexOf(a.room.id);
    final bRank = popularRoomRank.indexOf(b.room.id);
    final aScore = aRank < 0 ? popularRoomRank.length : aRank;
    final bScore = bRank < 0 ? popularRoomRank.length : bRank;
    final byRank = aScore.compareTo(bScore);
    if (byRank != 0) {
      return byRank;
    }
    return a.room.name.compareTo(b.room.name);
  });
  if (ranked.length <= 8) {
    return ranked;
  }
  return ranked.sublist(0, 8);
}
