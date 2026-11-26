import 'package:flutter/material.dart';

/// "G" do Google, desenhado com as quatro cores oficiais.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static final _paths = <(Color, Path)>[
    (
      const Color(0xFFEA4335),
      pathFromSvg(
        'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
      ),
    ),
    (
      const Color(0xFF4285F4),
      pathFromSvg(
        'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
      ),
    ),
    (
      const Color(0xFFFBBC05),
      pathFromSvg(
        'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
      ),
    ),
    (
      const Color(0xFF34A853),
      pathFromSvg(
        'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
      ),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 48;
    canvas.scale(scale);
    for (final (color, path) in _paths) {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Lê M, L, H, V, C, S e Z. O "G" usa curva suave (`s`).
Path pathFromSvg(String data) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsZz]|-?\d*\.?\d+(?:e-?\d+)?')
      .allMatches(data)
      .map((match) => match.group(0)!)
      .toList();
  var index = 0;
  String? command;
  var currentX = 0.0;
  var currentY = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var controlX = 0.0;
  var controlY = 0.0;
  var cubic = false;

  double number() => double.parse(tokens[index++]);

  void cubicTo(double x1, double y1, double x2, double y2, double x, double y) {
    path.cubicTo(x1, y1, x2, y2, x, y);
    controlX = x2;
    controlY = y2;
    currentX = x;
    currentY = y;
    cubic = true;
  }

  (double, double) reflected() {
    if (!cubic) return (currentX, currentY);
    return (2 * currentX - controlX, 2 * currentY - controlY);
  }

  while (index < tokens.length) {
    final token = tokens[index];
    if (RegExp(r'^[MmLlHhVvCcSsZz]$').hasMatch(token)) {
      command = token;
      index++;
    }
    if (command == null) break;
    switch (command) {
      case 'M':
        currentX = number();
        currentY = number();
        path.moveTo(currentX, currentY);
        startX = currentX;
        startY = currentY;
        cubic = false;
        command = 'L';
      case 'm':
        currentX += number();
        currentY += number();
        path.moveTo(currentX, currentY);
        startX = currentX;
        startY = currentY;
        cubic = false;
        command = 'l';
      case 'L':
        currentX = number();
        currentY = number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'l':
        currentX += number();
        currentY += number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'H':
        currentX = number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'h':
        currentX += number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'V':
        currentY = number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'v':
        currentY += number();
        path.lineTo(currentX, currentY);
        cubic = false;
      case 'C':
        final x1 = number();
        final y1 = number();
        final x2 = number();
        final y2 = number();
        final x = number();
        final y = number();
        cubicTo(x1, y1, x2, y2, x, y);
      case 'c':
        final x1 = currentX + number();
        final y1 = currentY + number();
        final x2 = currentX + number();
        final y2 = currentY + number();
        final x = currentX + number();
        final y = currentY + number();
        cubicTo(x1, y1, x2, y2, x, y);
      case 'S':
        final reflectedPoint = reflected();
        final x2 = number();
        final y2 = number();
        final x = number();
        final y = number();
        cubicTo(reflectedPoint.$1, reflectedPoint.$2, x2, y2, x, y);
      case 's':
        final reflectedPoint = reflected();
        final x2 = currentX + number();
        final y2 = currentY + number();
        final x = currentX + number();
        final y = currentY + number();
        cubicTo(reflectedPoint.$1, reflectedPoint.$2, x2, y2, x, y);
      case 'Z':
      case 'z':
        path.close();
        currentX = startX;
        currentY = startY;
        cubic = false;
      default:
        return path;
    }
  }
  return path;
}
