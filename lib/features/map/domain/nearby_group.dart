import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';

/// Um grupo se formando, com a distância até a pessoa.
class NearbyGroup {
  const NearbyGroup({
    required this.group,
    required this.house,
    required this.distanceKm,
  });

  final Group group;
  final EscapeHouse house;
  final double distanceKm;

  GeoPoint get point => GeoPoint(house.latitude, house.longitude);
}

/// Grupos na fase “se formando”, dentro do raio, do mais perto ao mais longe.
List<NearbyGroup> formingWithinRadius({
  required List<Group> groups,
  required List<EscapeHouse> houses,
  required GeoPoint origin,
  required double radiusKm,
  required DateTime now,
}) {
  final byHouse = {for (final house in houses) house.id: house};
  final nearby = <NearbyGroup>[];
  for (final group in groups) {
    if (group.phaseAt(now) != GroupPhase.forming) {
      continue;
    }
    final house = byHouse[group.houseId];
    if (house == null) {
      continue;
    }
    final distance = distanceKm(
      origin,
      GeoPoint(house.latitude, house.longitude),
    );
    if (distance > radiusKm) {
      continue;
    }
    nearby.add(NearbyGroup(group: group, house: house, distanceKm: distance));
  }
  nearby.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return nearby;
}

/// Cidade com grupo se formando cujo centro fica mais perto da pessoa.
///
/// Nulo quando nenhuma cidade tem grupo se formando.
String? nearestCityWithFormingGroups({
  required GeoPoint origin,
  required Map<String, GeoPoint> centers,
  required Iterable<Group> groups,
  required DateTime now,
}) {
  final formingCities = <String>{
    for (final group in groups)
      if (group.phaseAt(now) == GroupPhase.forming) group.cityId,
  };
  String? best;
  var bestKm = double.infinity;
  for (final cityId in formingCities) {
    final center = centers[cityId];
    if (center == null) {
      continue;
    }
    final km = distanceKm(origin, center);
    if (km < bestKm) {
      bestKm = km;
      best = cityId;
    }
  }
  return best;
}
