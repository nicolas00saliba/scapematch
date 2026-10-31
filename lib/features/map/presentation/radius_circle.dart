import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Círculo do raio em metros.
///
/// O [CircleLayer] do flutter_map pinta o disco com `drawPoints`. Na web,
/// e também no Skia quando o raio passa de uns cem pixels, esse ponto some.
/// `drawCircle` desenha o anel nos dois.
class RadiusCircleLayer extends StatelessWidget {
  const RadiusCircleLayer({
    super.key,
    required this.center,
    required this.radiusMeters,
  });

  final LatLng center;
  final double radiusMeters;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        painter: _RadiusCirclePainter(
          camera: camera,
          center: center,
          radiusMeters: radiusMeters,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RadiusCirclePainter extends CustomPainter {
  _RadiusCirclePainter({
    required this.camera,
    required this.center,
    required this.radiusMeters,
  });

  final MapCamera camera;
  final LatLng center;
  final double radiusMeters;

  static const _distance = Distance();
  static const _blue = Color(0xFF1A73E8);

  @override
  void paint(Canvas canvas, Size size) {
    if (radiusMeters <= 0 || !size.width.isFinite || size.width <= 0) {
      return;
    }
    final edge = _distance.offset(center, radiusMeters, 90);
    final origin = camera.latLngToScreenOffset(center);
    final radius = (camera.latLngToScreenOffset(edge) - origin).distance;
    if (!radius.isFinite || radius <= 0) {
      return;
    }
    canvas.drawCircle(
      origin,
      radius,
      Paint()..color = _blue.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xE6FFFFFF),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_RadiusCirclePainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.center != center ||
        oldDelegate.radiusMeters != radiusMeters;
  }
}
