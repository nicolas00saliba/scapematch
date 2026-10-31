import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/motion.dart';

/// Faixa de espera. Sem reduzir movimento, o brilho corre uma vez e recomeça.
///
/// O ciclo é curto de propósito: um controller eterno segura o pumpAndSettle
/// dos testes que ainda estão na tela de carregamento.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.width, this.height = 12, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (scapeAnimationsEnabled(context)) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final shine = scheme.surface;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final slide = _controller.value * 2 - 1;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 + slide, 0),
                end: Alignment(slide, 0),
                colors: [base, shine, base],
              ),
            ),
          );
        },
      ),
    );
  }
}
