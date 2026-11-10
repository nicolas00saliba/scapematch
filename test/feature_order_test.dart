import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/popular_rooms.dart';

void main() {
  test('destaque numerado vem antes do ranking de exemplo', () {
    final plain = _listing('room-cwb-opera', 'Ópera', null);
    final picked = _listing('sala-nova', 'Sala nova', 0);
    final ranked = rankPopularRooms([plain, picked]);
    expect(ranked.first.room.id, 'sala-nova');
  });

  test('sem destaque, a ordem de exemplo continua', () {
    final opera = _listing('room-cwb-opera', 'Ópera', null);
    final cofre = _listing('room-cwb-cofre', 'Cofre', null);
    final ranked = rankPopularRooms([opera, cofre]);
    expect(ranked.first.room.name, 'Cofre');
  });
}

RoomListing _listing(String id, String name, int? rank) {
  return RoomListing(
    room: EscapeRoom(
      id: id,
      houseId: 'casa',
      name: name,
      theme: '',
      category: RoomCategory.mystery,
      capacity: 4,
      minimumPlayers: 2,
      durationMinutes: 60,
      difficulty: Difficulty.medium,
      priceCents: 10000,
      featuredRank: rank,
    ),
    houseId: 'casa',
    houseName: 'Casa',
    cityId: 'curitiba',
    cityName: 'Curitiba',
  );
}
