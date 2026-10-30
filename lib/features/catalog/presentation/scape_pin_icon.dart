import 'package:flutter/material.dart';

/// Pino de localização no desenho do ScapeMatch.
///
/// O formato lembra um alfinete de mapa. As cores vêm do tema: roxo no
/// corpo, fundo da página no miolo e dourado no ponto.
class ScapePinIcon extends StatelessWidget {
  const ScapePinIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Localização',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ScapePinPainter(
            body: scheme.primary,
            hole: Theme.of(context).scaffoldBackgroundColor,
            dot: scheme.tertiary,
          ),
        ),
      ),
    );
  }
}

class _ScapePinPainter extends CustomPainter {
  const _ScapePinPainter({
    required this.body,
    required this.hole,
    required this.dot,
  });

  final Color body;
  final Color hole;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final radius = width * 0.38;
    final center = Offset(width / 2, radius + (height * 0.04));
    final paint = Paint()..color = body;
    canvas.drawCircle(center, radius, paint);

    final tip = Path()
      ..moveTo(center.dx - radius * 0.62, center.dy + radius * 0.42)
      ..lineTo(center.dx, height - (height * 0.02))
      ..lineTo(center.dx + radius * 0.62, center.dy + radius * 0.42)
      ..close();
    canvas.drawPath(tip, paint);
    canvas.drawCircle(center, radius * 0.42, Paint()..color = hole);
    canvas.drawCircle(center, radius * 0.18, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant _ScapePinPainter oldDelegate) {
    return oldDelegate.body != body ||
        oldDelegate.hole != hole ||
        oldDelegate.dot != dot;
  }
}
