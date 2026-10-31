import 'package:geolocator/geolocator.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/features/map/data/user_location.dart';

/// GPS do aparelho e do navegador. Sem permissão, devolve o centro da cidade.
class GeolocatorUserLocation implements UserLocationSource {
  @override
  Future<UserFix> current({required GeoPoint fallback}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return UserFix(point: fallback, read: LocationRead.unavailable);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return UserFix(point: fallback, read: LocationRead.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return UserFix(point: fallback, read: LocationRead.denied);
      }
      final position = await Geolocator.getCurrentPosition();
      return UserFix(
        point: GeoPoint(position.latitude, position.longitude),
        read: LocationRead.device,
      );
    } catch (_) {
      return UserFix(point: fallback, read: LocationRead.unavailable);
    }
  }
}
