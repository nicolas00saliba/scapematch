import 'dart:math' as math;

import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';

/// Uma casa no mapa, com o que o pino precisa desenhar.
class HousePin {
  const HousePin({
    required this.house,
    required this.priceCents,
    required this.formingCount,
    required this.groups,
  });

  final EscapeHouse house;
  final int? priceCents;
  final int formingCount;
  final List<Group> groups;

  double get latitude => house.latitude;
  double get longitude => house.longitude;
  bool get isForming => formingCount > 0;
}

/// Monta um pino por casa. O preço é o menor da casa no tipo escolhido.
/// A contagem é de grupos ainda na fase “se formando”.
List<HousePin> buildHousePins({
  required List<EscapeHouse> houses,
  required List<EscapeRoom> rooms,
  required List<Group> groups,
  required DateTime now,
  String gameTypeId = GameTypes.all,
}) {
  final visibleRooms = [
    for (final room in rooms)
      if (gameTypeId == GameTypes.all || room.gameType == gameTypeId) room,
  ];
  final pins = <HousePin>[];
  for (final house in houses) {
    int? price;
    for (final room in visibleRooms) {
      if (room.houseId != house.id) {
        continue;
      }
      final current = price;
      if (current == null || room.priceCents < current) {
        price = room.priceCents;
      }
    }
    final here = [
      for (final group in groups)
        if (group.houseId == house.id) group,
    ];
    pins.add(
      HousePin(
        house: house,
        priceCents: price,
        formingCount: formingGroupCount(here, now),
        groups: here,
      ),
    );
  }
  pins.sort((a, b) => a.house.name.compareTo(b.house.name));
  return pins;
}

/// Grupos cuja fase agora é “se formando”.
int formingGroupCount(List<Group> groups, DateTime now) {
  var count = 0;
  for (final group in groups) {
    if (group.phaseAt(now) == GroupPhase.forming) {
      count += 1;
    }
  }
  return count;
}

/// Escala do pulso. Com reduzir movimento, o pino fica parado.
double pinPulseScale({required double t, required bool enabled}) {
  if (!enabled) {
    return 1;
  }
  final wave = math.sin(t.clamp(0, 1) * math.pi);
  return 1 + (0.08 * wave);
}
