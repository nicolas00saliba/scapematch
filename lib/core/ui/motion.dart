import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Animações curtas. Com reduzir movimento, tudo vira instantâneo.
bool scapeAnimationsEnabled(BuildContext context) {
  return !MediaQuery.disableAnimationsOf(context);
}

Duration scapeDuration(BuildContext context, Duration duration) {
  if (!scapeAnimationsEnabled(context)) {
    return Duration.zero;
  }
  return duration;
}

/// Toque com leve encolhimento. A vibração só existe no celular.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = scapeAnimationsEnabled(context);
    return Listener(
      onPointerDown: (_) {
        _setPressed(true);
        if (!kIsWeb) {
          HapticFeedback.lightImpact().catchError((_) {});
        }
      },
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: enabled && _pressed ? 0.97 : 1,
        duration: scapeDuration(context, const Duration(milliseconds: 140)),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Entrada em cascata. Itens seguintes duram um pouco mais, sem timer solto.
class StaggerIn extends StatelessWidget {
  const StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = scapeAnimationsEnabled(context);
    final extra = enabled ? (index.clamp(0, 8)) * 35 : 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: enabled ? 0 : 1, end: 1),
      duration: Duration(milliseconds: enabled ? 240 + extra : 0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Conta de um número até o valor final. Com reduzir movimento, mostra o fim.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final enabled = scapeAnimationsEnabled(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: enabled ? 0 : value.toDouble(),
        end: value.toDouble(),
      ),
      duration: scapeDuration(context, const Duration(milliseconds: 420)),
      curve: Curves.easeOutCubic,
      builder: (context, current, _) {
        return Text('${current.round()}', style: style);
      },
    );
  }
}
