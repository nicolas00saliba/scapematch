import 'package:scapematch/core/geo/geo_point.dart';

/// O que o mapa sabe sobre a posição da pessoa.
enum LocationRead { device, denied, unavailable }

class UserFix {
  const UserFix({required this.point, required this.read});

  final GeoPoint point;
  final LocationRead read;

  bool get isDevice => read == LocationRead.device;
}

/// Lê a posição. O app usa o GPS; o teste entrega um ponto fixo.
abstract class UserLocationSource {
  Future<UserFix> current({required GeoPoint fallback});
}

/// Posição combinada, para o teste não pedir permissão.
class FixedUserLocation implements UserLocationSource {
  const FixedUserLocation.device(this.point) : read = LocationRead.device;

  const FixedUserLocation.denied(GeoPoint fallback)
    : point = fallback,
      read = LocationRead.denied;

  const FixedUserLocation.unavailable(GeoPoint fallback)
    : point = fallback,
      read = LocationRead.unavailable;

  final GeoPoint point;
  final LocationRead read;

  @override
  Future<UserFix> current({required GeoPoint fallback}) async {
    if (read == LocationRead.device) {
      return UserFix(point: point, read: read);
    }
    return UserFix(point: fallback, read: read);
  }
}
