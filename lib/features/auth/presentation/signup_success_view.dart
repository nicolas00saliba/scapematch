import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';

/// Confirmação depois do cadastro real: check verde, o e-mail que
/// recebeu o link e os dois caminhos (entrar ou pedir o e-mail de novo).
///
/// A espera começa agora, porque o Auth acabou de enviar. Outro toque
/// em "Reenviar e-mail" só vale quando [cooldown] zera, e zera de novo
/// depois de cada pedido.
class SignupSuccessView extends StatefulWidget {
  const SignupSuccessView({
    super.key,
    required this.email,
    required this.onLogin,
    required this.onResend,
    this.cooldown = signupResendCooldown,
  });

  final String email;
  final VoidCallback onLogin;

  /// Nulo quando o reenvio saiu. A frase volta na tela.
  final Future<String?> Function() onResend;
  final Duration cooldown;

  @override
  State<SignupSuccessView> createState() => _SignupSuccessViewState();
}

class _SignupSuccessViewState extends State<SignupSuccessView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _check;
  Timer? _timer;
  var _remaining = 0;
  var _busy = false;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _armCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _check.dispose();
    super.dispose();
  }

  void _armCooldown() {
    _timer?.cancel();
    final seconds = widget.cooldown.inSeconds;
    if (seconds <= 0) {
      _remaining = 0;
      return;
    }
    _remaining = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) timer.cancel();
      });
    });
  }

  String? _statusLine(bool waiting) {
    final wait = 'Você pode reenviar em ${_remaining}s.';
    if (_error != null && !waiting) return _error;
    final notice = _notice;
    if (waiting && notice != null) return '$notice $wait';
    if (waiting) return wait;
    return notice;
  }

  Future<void> _resend() async {
    if (_remaining > 0 || _busy) return;
    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
    });
    final error = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _notice = signupResendNeutralMessage;
        _error = null;
        _armCooldown();
      } else {
        _error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ScapeStatusColors.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.45,
    );
    final waiting = _remaining > 0;
    final statusText = _statusLine(waiting);
    return ListView(
      key: AppKeys.signupSuccess,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(
            CurvedAnimation(parent: _check, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _check, curve: Curves.easeOut),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: status.successContainer,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 196,
                  height: 196,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _check,
                      builder: (context, _) {
                        return CustomPaint(
                          key: AppKeys.signupSuccessCheck,
                          size: const Size(112, 112),
                          painter: _CheckPainter(
                            progress: Curves.easeOut.transform(_check.value),
                            color: status.success,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Conta criada',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: body,
            children: [
              const TextSpan(text: 'Confirme o e-mail que enviamos para '),
              TextSpan(
                text: widget.email,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const TextSpan(text: ' e depois entre.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(
          key: AppKeys.signupGoToLogin,
          onPressed: widget.onLogin,
          child: const Text('Ir para o login'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: AppKeys.signupResendEmail,
          onPressed: waiting || _busy ? null : _resend,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            side: BorderSide(
              color: waiting || _busy ? scheme.outlineVariant : scheme.primary,
              width: 1.5,
            ),
            foregroundColor: scheme.primary,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'Roboto',
            ),
          ),
          child: const Text('Reenviar e-mail'),
        ),
        if (waiting || statusText != null) ...[
          const SizedBox(height: 12),
          Text(
            statusText!,
            key: AppKeys.signupResendStatus,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _error != null && !waiting
                  ? scheme.error
                  : scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.84, size.height * 0.28);
    for (final metric in path.computeMetrics()) {
      final drawn = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(drawn, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
