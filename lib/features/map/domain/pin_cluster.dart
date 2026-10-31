import 'dart:math' as math;

import 'package:scapematch/features/map/domain/house_pin.dart';

/// Pinos que caem no mesmo ponto da tela viram um só.
class PinCluster {
  const PinCluster(this.pins);

  final List<HousePin> pins;

  bool get isCluster => pins.length > 1;

  String get id => [for (final pin in pins) pin.house.id].join('+');

  double get latitude {
    var sum = 0.0;
    for (final pin in pins) {
      sum += pin.latitude;
    }
    return sum / pins.length;
  }

  double get longitude {
    var sum = 0.0;
    for (final pin in pins) {
      sum += pin.longitude;
    }
    return sum / pins.length;
  }
}

/// Agrupa pinos cuja distância na tela, no [zoom] atual, cabe em
/// [radiusPixels]. A ordem de entrada não muda o resultado: a lista é
/// ordenada pelo id da casa.
List<PinCluster> clusterHousePins(
  List<HousePin> pins, {
  required double zoom,
  double radiusPixels = 48,
}) {
  final pending = [...pins]..sort((a, b) => a.house.id.compareTo(b.house.id));
  final clusters = <PinCluster>[];
  while (pending.isNotEmpty) {
    final seed = pending.removeAt(0);
    final group = <HousePin>[seed];
    pending.removeWhere((other) {
      if (_pixelDistance(seed, other, zoom) <= radiusPixels) {
        group.add(other);
        return true;
      }
      return false;
    });
    clusters.add(PinCluster(group));
  }
  return clusters;
}

double _pixelDistance(HousePin a, HousePin b, double zoom) {
  final ax = _worldX(a.longitude, zoom);
  final ay = _worldY(a.latitude, zoom);
  final bx = _worldX(b.longitude, zoom);
  final by = _worldY(b.latitude, zoom);
  final dx = ax - bx;
  final dy = ay - by;
  return math.sqrt((dx * dx) + (dy * dy));
}

double _worldX(double longitude, double zoom) {
  return (longitude + 180) / 360 * 256 * math.pow(2, zoom);
}

double _worldY(double latitude, double zoom) {
  final radians = latitude * math.pi / 180;
  final sine = math.sin(radians);
  final y = 0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi);
  return y * 256 * math.pow(2, zoom);
}
