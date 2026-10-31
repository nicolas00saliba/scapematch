import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/motion.dart';

/// Ponto azul com ondas, no jeito de um mapa. Com reduzir movimento, só o ponto.
class UserDot extends StatefulWidget {
  const UserDot({super.key, this.animate = true});

  final bool animate;

  @override
  State<UserDot> createState() => _UserDotState();
}

class _UserDotState extends State<UserDot> {
  Timer? _timer;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pulse = widget.animate && scapeAnimationsEnabled(context);
    if (pulse && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (mounted) {
          setState(() => _generation += 1);
        }
      });
    } else if (!pulse) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(UserDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      didChangeDependencies();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = widget.animate && scapeAnimationsEnabled(context);
    if (!pulse) {
      return const RepaintBoundary(child: _DotFace(t: 1));
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(_generation),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeOut,
      builder: (context, t, _) {
        return RepaintBoundary(child: _DotFace(t: t));
      },
    );
  }
}

class _DotFace extends StatelessWidget {
  const _DotFace({required this.t});

  final double t;

  static const _blue = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var ring = 0; ring < 3; ring++) _ring((t + ring / 3) % 1),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x551A73E8), blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double phase) {
    final size = 22 + (phase * 78);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _blue.withValues(alpha: (1 - phase) * 0.55),
          width: 2,
        ),
      ),
    );
  }
}
