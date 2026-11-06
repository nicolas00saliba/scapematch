import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/window_class.dart';

/// Abertura do celular.
///
/// Cobre o app uma vez por processo: abrir, recarregar a página ou abrir
/// o PWA de novo. Trocar de tela, voltar, um deep link interno e um resume
/// curto (o app ainda na memória) não repetem. Não grava flag. A introdução
/// continua com a chave dela.
///
/// A capa entra: floresta, círculo petróleo e “ScapeMatch”. O restante
/// converge para o pin. O pin se aproxima e gira no próprio eixo vertical,
/// como um pião, crescendo até sumir. Só então a cortina revela a próxima
/// tela. Com reduzir movimento, a capa já entra pronta e a cortina some em
/// [reducedDuration], sem giro.
///
/// O site, a partir de [scapeDesktopMinWidth], não mostra. A sessão e o
/// login seguem por baixo; a cortina só esconde o primeiro instante.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  /// Noite da capa, atrás da arte quando ela encolhe.
  static const background = Color(0xFF142046);
  static const copper = Color(0xFF9A4F24);

  static const coverAsset = 'assets/brand/capa_app.jpg';

  /// Entrada, pausa, convergência, giro e saída. Cabe em até 1,8s.
  static const duration = Duration(milliseconds: 1800);

  /// `prefers-reduced-motion`: o logo já está pronto e a cortina some.
  static const reducedDuration = Duration(milliseconds: 180);

  static const enterEnd = 0.16;
  static const holdEnd = 0.30;
  static const buryEnd = 0.48;
  static const approachEnd = 0.58;
  static const spinEnd = 0.82;
  static const vanishEnd = 0.90;

  static const enterScale = 0.9;
  static const restScale = 1.0;
  static const approachScale = 1.14;
  static const spinScale = 2.55;
  static const exitScale = 4.6;
  static const approachTurns = 0.08;
  static const spinTurns = 1.25;
  static const exitTurns = 1.55;

  /// Perspectiva leve do giro de pião. O pin continua de frente quando
  /// [turns] é 0; o valor só aparece de lado.
  static const yawPerspective = 0.003;

  static const curtainKey = Key('splash-curtain');
  static const coverKey = Key('splash-cover');
  static const logoOpacityKey = Key('splash-logo');
  static const scaleKey = Key('splash-scale');
  static const spinKey = Key('splash-spin');

  @override
  State<SplashGate> createState() => _SplashGateState();
}

/// Pose da splash em [t], de 0 a 1.
class SplashMotion {
  const SplashMotion({
    required this.logoOpacity,
    required this.cover,
    required this.coverScale,
    required this.absorb,
    required this.scale,
    required this.turns,
    required this.curtain,
  });

  /// Opacidade do pin. A capa pode continuar por cima no começo.
  final double logoOpacity;

  /// Opacidade da capa inteira. 0 quando ela já entrou no pin.
  final double cover;

  /// Escala da capa. 1 é o tamanho em que ela aparece.
  final double coverScale;

  /// 0 é a capa inteira. 1 é o instante em que o resto já entrou no pin.
  final double absorb;

  /// Escala do símbolo. 1 é o tamanho de repouso.
  final double scale;

  /// Voltas do pião, no eixo vertical. 0 não gira.
  final double turns;

  /// 1 cobre a próxima tela. 0 a revela.
  final double curtain;
}

double _span(double t, double start, double end) {
  if (end <= start) {
    return t >= end ? 1 : 0;
  }
  return ((t - start) / (end - start)).clamp(0.0, 1.0);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Movimento da splash. [reduced] é a versão curta, sem giro.
SplashMotion splashMotion(double t, {required bool reduced}) {
  final progress = t.clamp(0.0, 1.0);
  if (reduced) {
    return SplashMotion(
      logoOpacity: 0,
      cover: 1,
      coverScale: SplashGate.restScale,
      absorb: 0,
      scale: SplashGate.restScale,
      turns: 0,
      curtain: (1 - Curves.easeOut.transform(progress)).clamp(0.0, 1.0),
    );
  }

  final enter = Curves.easeOutCubic.transform(
    _span(progress, 0, SplashGate.enterEnd),
  );
  final bury = Curves.easeInCubic.transform(
    _span(progress, SplashGate.holdEnd, SplashGate.buryEnd),
  );
  final approach = Curves.easeOut.transform(
    _span(progress, SplashGate.buryEnd, SplashGate.approachEnd),
  );
  final spin = _span(progress, SplashGate.approachEnd, SplashGate.spinEnd);
  final vanish = Curves.easeIn.transform(
    _span(progress, SplashGate.spinEnd, SplashGate.vanishEnd),
  );

  final cover = progress <= SplashGate.holdEnd ? enter : 1 - bury;
  final logoOpacity = progress <= SplashGate.holdEnd
      ? 0.0
      : progress >= SplashGate.spinEnd
      ? 1 - vanish
      : bury;
  final double coverScale;
  if (progress <= SplashGate.enterEnd) {
    coverScale = _lerp(SplashGate.enterScale, SplashGate.restScale, enter);
  } else if (progress <= SplashGate.holdEnd) {
    coverScale = SplashGate.restScale;
  } else {
    coverScale = _lerp(SplashGate.restScale, 0.08, bury);
  }

  final double scale;
  if (progress <= SplashGate.enterEnd) {
    scale = _lerp(SplashGate.enterScale, SplashGate.restScale, enter);
  } else if (progress <= SplashGate.buryEnd) {
    scale = SplashGate.restScale;
  } else if (progress <= SplashGate.approachEnd) {
    scale = _lerp(SplashGate.restScale, SplashGate.approachScale, approach);
  } else if (progress <= SplashGate.spinEnd) {
    // Linear no tempo: o símbolo cresce enquanto gira.
    scale = _lerp(SplashGate.approachScale, SplashGate.spinScale, spin);
  } else {
    scale = _lerp(SplashGate.spinScale, SplashGate.exitScale, vanish);
  }

  final double turns;
  if (progress <= SplashGate.buryEnd) {
    turns = 0;
  } else if (progress <= SplashGate.approachEnd) {
    turns = _lerp(0, SplashGate.approachTurns, approach);
  } else if (progress <= SplashGate.spinEnd) {
    turns = _lerp(SplashGate.approachTurns, SplashGate.spinTurns, spin);
  } else {
    turns = _lerp(SplashGate.spinTurns, SplashGate.exitTurns, vanish);
  }

  final curtain = progress <= SplashGate.vanishEnd
      ? 1.0
      : (1 -
                Curves.easeInOutCubic.transform(
                  _span(progress, SplashGate.vanishEnd, 1),
                ))
            .clamp(0.0, 1.0);

  return SplashMotion(
    logoOpacity: logoOpacity.clamp(0.0, 1.0),
    cover: cover.clamp(0.0, 1.0),
    coverScale: coverScale,
    absorb: bury,
    scale: scale,
    turns: turns,
    curtain: curtain,
  );
}

/// Giro no eixo vertical do símbolo. Não é rotação no plano da tela.
Matrix4 splashYawTransform(double turns) {
  return Matrix4.identity()
    ..setEntry(3, 2, SplashGate.yawPerspective)
    ..rotateY(turns * 2 * math.pi);
}

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
                final motion = splashMotion(animation.value, reduced: reduced);
                return Opacity(
                  key: SplashGate.curtainKey,
                  opacity: motion.curtain,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: _overlay,
                    child: ColoredBox(
                      color: SplashGate.background,
                      // Sem um Material, o letreiro herda o estilo de erro
                      // (sublinhado amarelo) do MaterialApp.
                      child: Material(
                        type: MaterialType.transparency,
                        child: SizedBox.expand(
                          child: _SplashMark(motion: motion),
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
  const _SplashMark({required this.motion});

  final SplashMotion motion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          constraints.maxWidth,
          constraints.maxHeight * 240 / 242,
        );
        final coverHeight = side * 242 / 240;
        final pinHeight = side * 72 / 240;
        const anchor = Alignment(0, -0.25);
        return Center(
          child: SizedBox(
            width: side,
            height: coverHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Opacity(
                  key: SplashGate.coverKey,
                  opacity: motion.cover,
                  child: Transform.scale(
                    alignment: anchor,
                    scale: motion.coverScale,
                    filterQuality: FilterQuality.medium,
                    child: Image.asset(
                      SplashGate.coverAsset,
                      width: side,
                      height: coverHeight,
                      fit: BoxFit.fill,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                Align(
                  alignment: anchor,
                  child: Opacity(
                    key: SplashGate.logoOpacityKey,
                    opacity: motion.logoOpacity,
                    child: Transform.scale(
                      key: SplashGate.scaleKey,
                      scale: motion.scale,
                      child: Transform(
                        key: SplashGate.spinKey,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.medium,
                        transform: splashYawTransform(motion.turns),
                        child: ScapeLogo(
                          variant: ScapeLogoVariant.mark,
                          height: pinHeight,
                          onDark: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
