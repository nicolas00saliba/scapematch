import 'dart:math' as math;

/// Um ponto. As casas de exemplo usam isto; a pessoa também, quando o
/// aparelho entrega a localização.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Centros das cidades de exemplo. O mapa cai aqui quando não há GPS.
const cityCenters = <String, GeoPoint>{
  'curitiba': GeoPoint(-25.4284, -49.2733),
  'sao-paulo': GeoPoint(-23.5505, -46.6333),
  'rio-de-janeiro': GeoPoint(-22.9068, -43.1729),
  'belo-horizonte': GeoPoint(-19.9167, -43.9345),
  'porto-alegre': GeoPoint(-30.0346, -51.2177),
};

/// Distância em quilômetros, pelo haversine.
double distanceKm(GeoPoint a, GeoPoint b) {
  const earthKm = 6371.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final lat1 = _rad(a.latitude);
  final lat2 = _rad(b.latitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return earthKm * 2 * math.asin(math.min(1, math.sqrt(h.toDouble())));
}

/// “800 m” ou “1,2 km”.
String formatDistanceKm(double kilometers) {
  if (kilometers < 1) {
    final meters = (kilometers * 1000).round();
    return '$meters m';
  }
  final text = kilometers.toStringAsFixed(1).replaceAll('.', ',');
  return '$text km';
}

/// Desloca um ponto em quilômetros. Norte é o rumo 0.
GeoPoint offsetKm(
  GeoPoint origin, {
  required double kilometers,
  required double bearingDegrees,
}) {
  final bearing = _rad(bearingDegrees);
  final lat = origin.latitude + (kilometers / 111.0) * math.cos(bearing);
  final lngScale = 111.0 * math.cos(_rad(origin.latitude));
  final lng = origin.longitude + (kilometers / lngScale) * math.sin(bearing);
  return GeoPoint(lat, lng);
}

double _rad(double degrees) => degrees * math.pi / 180;
