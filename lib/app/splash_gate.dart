import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/window_class.dart';

/// Abertura do celular, no jeito iFood/99.
///
/// Cobre o app uma vez por processo: abrir, recarregar a página ou abrir
/// o PWA de novo. Trocar de tela, voltar, um deep link interno e um resume
/// curto (o app ainda na memória) não repetem. Não grava flag. A introdução
/// continua com a chave dela.
///
/// O site, a partir de [scapeDesktopMinWidth], não mostra. A sessão e o
/// login seguem por baixo; a cortina só esconde o primeiro instante.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  static const background = Color(0xFF0F4C4A);
  static const copper = Color(0xFF9A4F24);

  /// Fade, pausa e saída. Cabe na faixa de 1,2–1,8s.
  static const duration = Duration(milliseconds: 1500);

  /// `prefers-reduced-motion`: o logo já entra pronto e a cortina some rápido.
  static const reducedDuration = Duration(milliseconds: 180);

  /// Fim da entrada do logo (fade + scale), em fração da [duration].
  static const enterEnd = 0.46;

  /// Início da saída da cortina, em fração da [duration].
  static const exitStart = 0.72;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

/// Quanto o logo já entrou, de 0 a 1.
double splashLogoEnter(double t, {required bool reduced}) {
  if (reduced) {
    return 1;
  }
  final x = (t / SplashGate.enterEnd).clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(x);
}

/// Opacidade da cortina. 1 cobre a próxima tela; 0 a revela.
double splashCurtainOpacity(double t, {required bool reduced}) {
  final progress = t.clamp(0.0, 1.0);
  if (reduced) {
    return (1 - Curves.easeOut.transform(progress)).clamp(0.0, 1.0);
  }
  if (progress <= SplashGate.exitStart) {
    return 1;
  }
  final x = (progress - SplashGate.exitStart) / (1 - SplashGate.exitStart);
  return (1 - Curves.easeInOutCubic.transform(x)).clamp(0.0, 1.0);
}

/// Scale suave: começa um pouco menor e assenta em 1.
double splashLogoScale(double enter) => 0.9 + 0.1 * enter;

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _decided = false;
  var _show = false;
  var _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SplashGate.duration,
      // O motor encolhe a duração para 5% quando o sistema pede menos
      // movimento. A abertura já tem a própria duração curta; sem isto,
      // o fade de 180ms viraria um único frame.
      animationBehavior: AnimationBehavior.preserve,
      debugLabel: 'splash',
    );
    _controller.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || !_show) {
      return;
    }
    setState(() => _show = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    // O primeiro frame da web às vezes chega com largura 0. Esperar a
    // medida real evita um flash verde no site.
    if (width <= 0) {
      return;
    }
    final desktop = isScapeDesktop(context);
    if (!_decided) {
      _decided = true;
      _reduced = !scapeAnimationsEnabled(context);
      if (desktop) {
        return;
      }
      _show = true;
      _controller.duration = _reduced
          ? SplashGate.reducedDuration
          : SplashGate.duration;
      _controller.forward();
      return;
    }
    // Girou para o site no meio da abertura: a splash é só do celular.
    if (_show && desktop) {
      _controller.stop();
      _show = false;
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: _show, child: widget.child),
        if (_show) _SplashCurtain(animation: _controller, reduced: _reduced),
      ],
    );
  }
}

class _SplashCurtain extends StatelessWidget {
  const _SplashCurtain({required this.animation, required this.reduced});

  final Animation<double> animation;
  final bool reduced;

  static const _overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: SplashGate.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: RepaintBoundary(
        key: AppKeys.splash,
        child: Semantics(
          label: 'ScapeMatch',
          container: true,
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value;
                final enter = splashLogoEnter(t, reduced: reduced);
                final curtain = splashCurtainOpacity(t, reduced: reduced);
                return Opacity(
                  opacity: curtain,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: _overlay,
                    child: ColoredBox(
                      color: SplashGate.background,
                      // Sem um Material, o letreiro herda o estilo de erro
                      // (sublinhado amarelo) do MaterialApp.
                      child: Material(
                        type: MaterialType.transparency,
                        child: SizedBox.expand(
                          child: _SplashMark(enter: enter),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark({required this.enter});

  final double enter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: enter,
              child: Transform.scale(
                scale: splashLogoScale(enter),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ScapeLogo(height: 80, onDark: true),
                ),
              ),
            ),
            const SizedBox(height: 22),
            ColoredBox(
              color: SplashGate.copper,
              child: SizedBox(width: 72 * enter, height: 3),
            ),
          ],
        ),
      ),
    );
  }
}
