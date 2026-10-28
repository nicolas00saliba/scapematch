import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';

/// Pino de localização no desenho do ScapeMatch.
///
/// O formato lembra um alfinete de mapa. As cores são o verde e o cobre
/// do tema, não o ícone do Google nem um emoji.
class ScapePinIcon extends StatelessWidget {
  const ScapePinIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Localização',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ScapePinPainter()),
      ),
    );
  }
}

class _ScapePinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final radius = width * 0.38;
    final center = Offset(width / 2, radius + (height * 0.04));
    final body = Paint()..color = AppColors.teal;
    canvas.drawCircle(center, radius, body);

    final tip = Path()
      ..moveTo(center.dx - radius * 0.62, center.dy + radius * 0.42)
      ..lineTo(center.dx, height - (height * 0.02))
      ..lineTo(center.dx + radius * 0.62, center.dy + radius * 0.42)
      ..close();
    canvas.drawPath(tip, body);
    canvas.drawCircle(center, radius * 0.42, Paint()..color = AppColors.cream);
    canvas.drawCircle(center, radius * 0.18, Paint()..color = AppColors.copper);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
