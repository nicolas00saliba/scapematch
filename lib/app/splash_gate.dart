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
/// Primeiro entra o logo completo (pin oficial e letreiro), parado o
/// bastante para ler. O letreiro entra no pin como um trem. O Parceiro
/// pode pôr um selo embaixo; ele desliza no mesmo trem e some ao tocar o
/// corpo do pin. Só então o pin avança, gira no eixo vertical e cresce
/// até sumir. A escala é uniforme, na proporção do viewBox, então o disco
/// branco continua circular. A cortina só revela a próxima tela depois
/// disso. Com reduzir movimento, o logo completo já entra pronto e a
/// cortina some em [reducedDuration], sem trem e sem giro.
///
/// O site, a partir de [scapeDesktopMinWidth], não mostra. A sessão e o
/// login seguem por baixo; a cortina só esconde o primeiro instante.
/// Selo sob o lockup. [absorb] é o mesmo do letreiro: 0 parado, 1 já no pin.
typedef SplashLockupFooter = Widget Function(
  BuildContext context,
  double logoHeight,
  double absorb,
);

/// Altura do selo, incluindo o vão. O giro usa este valor para sair do pin.
typedef SplashLockupFooterExtent = double Function(
  BuildContext context,
  double logoHeight,
);

class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.markImage,
    this.curtain = background,
    this.onDark = false,
    this.lockupFooter,
    this.lockupFooterExtent,
  }) : assert(
         (lockupFooter == null) == (lockupFooterExtent == null),
         'O selo da abertura precisa do desenho e da altura juntos.',
       );

  final Widget child;

  /// Troca só a arte do pin. Nulo é o SVG do jogador. O movimento não muda.
  final ImageProvider? markImage;

  /// Cor da cortina. O jogador fica no branco. O Parceiro usa o preto do logo.
  final Color curtain;

  /// Letreiro claro, para a cortina preta. O jogador deixa falso.
  final bool onDark;

  /// Peça extra sob o logo completo. O jogador deixa nulo: a abertura dele
  /// não ganha selo. O Parceiro põe o selo "Parceiro", que entra no pin
  /// junto com o letreiro.
  final SplashLockupFooter? lockupFooter;

  /// Altura de [lockupFooter] para o logo caber na tela e o giro sair do pin.
  final SplashLockupFooterExtent? lockupFooterExtent;

  /// Fundo da abertura. O disco do pin também é branco.
  static const background = Color(0xFFFFFFFF);
  static const copper = Color(0xFF9A4F24);

  /// Entrada, leitura do letreiro, trem, aproximação, giro e saída.
  /// Um pouco mais lenta que os 1800ms em que o letreiro não aparecia.
  static const duration = Duration(milliseconds: 2700);

  /// `prefers-reduced-motion`: o logo completo já está pronto e a cortina some.
  static const reducedDuration = Duration(milliseconds: 180);

  static const enterEnd = 0.12;
  static const holdEnd = 0.36;
  static const buryEnd = 0.56;
  static const approachEnd = 0.66;
  static const spinEnd = 0.86;
  static const vanishEnd = 0.93;

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
    required this.recenter,
    required this.scale,
    required this.turns,
    required this.curtain,
  });

  /// Opacidade do arquivo da capa. O pin e o branco usam o mesmo valor.
  final double logoOpacity;

  /// Opacidade do mesmo arquivo. Igual a [logoOpacity].
  final double cover;

  /// Escala uniforme do arquivo. Igual a [scale], sem esticar o disco.
  final double coverScale;

  /// 0 é o letreiro ao lado. 1 é o letreiro já dentro do pin.
  final double absorb;

  /// 0 mantém o pin onde o logo completo o deixou. 1 o traz ao centro
  /// da tela, depois do trem, para o giro sair do meio.
  final double recenter;

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
      logoOpacity: 1,
      cover: 1,
      coverScale: SplashGate.restScale,
      absorb: 0,
      recenter: 0,
      scale: SplashGate.restScale,
      turns: 0,
      curtain: (1 - Curves.easeOut.transform(progress)).clamp(0.0, 1.0),
    );
  }

  final enter = Curves.easeOutCubic.transform(
    _span(progress, 0, SplashGate.enterEnd),
  );
  final bury = Curves.easeInOutCubic.transform(
    _span(progress, SplashGate.holdEnd, SplashGate.buryEnd),
  );
  final recenter = Curves.easeInOut.transform(
    _span(progress, SplashGate.buryEnd, SplashGate.approachEnd),
  );
  final approach = Curves.easeOut.transform(
    _span(progress, SplashGate.buryEnd, SplashGate.approachEnd),
  );
  final spin = _span(progress, SplashGate.approachEnd, SplashGate.spinEnd);
  final vanish = Curves.easeIn.transform(
    _span(progress, SplashGate.spinEnd, SplashGate.vanishEnd),
  );

  // Um arquivo só: o pin e o branco entram juntos e ficam até sumir.
  final shown = progress <= SplashGate.enterEnd
      ? enter
      : progress >= SplashGate.spinEnd
      ? 1 - vanish
      : 1.0;
  final cover = shown;
  final logoOpacity = shown;

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
    coverScale: scale,
    absorb: bury,
    recenter: recenter,
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
        if (_show)
          _SplashCurtain(
            animation: _controller,
            reduced: _reduced,
            markImage: widget.markImage,
            curtain: widget.curtain,
            onDark: widget.onDark,
            lockupFooter: widget.lockupFooter,
            lockupFooterExtent: widget.lockupFooterExtent,
          ),
      ],
    );
  }
}

class _SplashCurtain extends StatelessWidget {
  const _SplashCurtain({
    required this.animation,
    required this.reduced,
    required this.markImage,
    required this.curtain,
    required this.onDark,
    required this.lockupFooter,
    required this.lockupFooterExtent,
  });

  final Animation<double> animation;
  final bool reduced;
  final ImageProvider? markImage;
  final Color curtain;
  final bool onDark;
  final SplashLockupFooter? lockupFooter;
  final SplashLockupFooterExtent? lockupFooterExtent;

  SystemUiOverlayStyle get _overlay {
    final light = curtain.computeLuminance() > 0.5;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: curtain,
      systemNavigationBarIconBrightness: light
          ? Brightness.dark
          : Brightness.light,
    );
  }

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
                      color: curtain,
                      // Sem um Material, o letreiro herda o estilo de erro
                      // (sublinhado amarelo) do MaterialApp.
                      child: Material(
                        type: MaterialType.transparency,
                        child: SizedBox.expand(
                          child: _SplashMark(
                            motion: motion,
                            markImage: markImage,
                            onDark: onDark,
                            lockupFooter: lockupFooter,
                            lockupFooterExtent: lockupFooterExtent,
                          ),
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
  const _SplashMark({
    required this.motion,
    required this.markImage,
    required this.onDark,
    required this.lockupFooter,
    required this.lockupFooterExtent,
  });

  final SplashMotion motion;
  final ImageProvider? markImage;
  final bool onDark;
  final SplashLockupFooter? lockupFooter;
  final SplashLockupFooterExtent? lockupFooterExtent;

  double _heightThatFits(BuildContext context, BoxConstraints constraints) {
    final maxW = math.max(0.0, constraints.maxWidth - 64);
    final maxH = math.max(0.0, constraints.maxHeight - 64);
    if (maxW <= 0 || maxH <= 0) {
      return 1;
    }
    final extentFor = lockupFooterExtent;
    var lo = 1.0;
    var hi = maxH;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      final footer = extentFor?.call(context, mid) ?? 0;
      // Sem selo, footer é 0 e mid já está abaixo de maxH: o mesmo encaixe
      // de antes, só pela largura do lockup.
      if (ScapeLogo.lockupWidthFor(context, mid) <= maxW &&
          mid + footer <= maxH) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = _heightThatFits(context, constraints);
        final pinW = ScapeLogo.pinWidthFor(height);
        final fullW = ScapeLogo.lockupWidthFor(context, height);
        final footer = lockupFooter;
        final footerH = footer == null
            ? 0.0
            : lockupFooterExtent!(context, height);
        // O giro e o crescimento saem do centro do pin, não do letreiro
        // nem do selo que fica embaixo.
        final alignX = fullW == 0 ? 0.0 : pinW / fullW - 1;
        final columnH = height + footerH;
        final alignY = footerH == 0 || columnH == 0 ? 0.0 : -footerH / columnH;
        final alignment = Alignment(alignX, alignY);
        // Depois do trem, o pin vai ao centro. Antes disso ele fica parado
        // para o letreiro (e o selo, se houver) entrar nele.
        final shift = (fullW - pinW) / 2 * motion.recenter;
        final drop = footerH / 2 * motion.recenter;
        final logo = ScapeLogo(
          height: height,
          onDark: onDark,
          wordmarkAbsorb: motion.absorb,
          markImage: markImage,
        );
        final Widget mark = footer == null
            ? logo
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [logo, footer(context, height, motion.absorb)],
              );
        return Center(
          child: Transform.translate(
            offset: Offset(shift, drop),
            child: Opacity(
              key: SplashGate.logoOpacityKey,
              opacity: motion.logoOpacity,
              child: Transform.scale(
                key: SplashGate.scaleKey,
                alignment: alignment,
                scale: motion.scale,
                filterQuality: FilterQuality.medium,
                child: Transform(
                  key: SplashGate.spinKey,
                  alignment: alignment,
                  filterQuality: FilterQuality.medium,
                  transform: splashYawTransform(motion.turns),
                  child: mark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
