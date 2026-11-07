import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

/// Pílula "Parceiro": cobre da marca, fundo pêssego e cantos fechados.
///
/// O topo compacto e o lockup usam este mesmo selo. No claro, o pêssego é
/// o cobre a 14% sobre a página. No preto da abertura o mesmo cobre some,
/// então o fundo vira o pêssego já misturado com o creme da página.
class PartnerSeal extends StatelessWidget {
  const PartnerSeal({
    super.key,
    required this.fontSize,
    this.ink,
    this.solidPeach = false,
    this.scaleText = true,
  });

  final double fontSize;

  /// Nulo segue o tema: cobre no claro, creme no escuro.
  final Color? ink;

  /// Pêssego opaco do print. A abertura preta precisa dele para o texto
  /// cobre continuar legível.
  final bool solidPeach;

  /// Falso quando [fontSize] já inclui o text scale. O trem da abertura
  /// mede a pílula com o mesmo número.
  final bool scaleText;

  static const label = 'Parceiro';
  static const lockupKey = Key('partner-lockup-seal');
  static const markKey = Key('partner-mark-seal');
  static const splashKey = Key('partner-splash-seal');

  /// Mesma borda do selo do topo. No print ela lê como ~2px físicos.
  static const borderWidth = 1.2;
  static const fillAlpha = 0.14;

  /// Letreiro do lockup usa 0,52 da altura. O selo fica menor, embaixo.
  static const lockupFontFactor = 0.28;

  static const _markFontFactor = 0.32;
  static const _markPadH = 0.22;
  static const _markPadV = 0.08;

  /// Creme da página clara. O pêssego do print é o cobre a 14% sobre ele.
  static const pageCream = Color(0xFFF5F1EA);

  static final Color peach = Color.alphaBlend(
    ScapeLogo.copper.withValues(alpha: fillAlpha),
    pageCream,
  );

  static double fontFor(double logoHeight) => logoHeight * lockupFontFactor;

  static double gapFor(double logoHeight) =>
      ScapeLogo.wordmarkGapFor(logoHeight);

  static double padH(double fontSize) =>
      fontSize * (_markPadH / _markFontFactor);

  static double padV(double fontSize) =>
      fontSize * (_markPadV / _markFontFactor);

  static TextStyle textStyle(double fontSize, Color color) {
    return TextStyle(
      color: color,
      fontFamily: 'Roboto',
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
  }

  static double pillHeight(
    BuildContext context,
    double fontSize, {
    bool scaleText = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle(fontSize, ScapeLogo.copper)),
      textDirection: Directionality.of(context),
      textScaler: scaleText
          ? MediaQuery.textScalerOf(context)
          : TextScaler.noScaling,
    )..layout();
    return painter.height + padV(fontSize) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final color = solidPeach
        ? ScapeLogo.copper
        : (ink ?? (themeDark ? ScapeLogo.pinOnDark : ScapeLogo.copper));
    final fill = solidPeach ? peach : color.withValues(alpha: fillAlpha);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: borderWidth),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padH(fontSize),
          vertical: padV(fontSize),
        ),
        child: Text(
          label,
          textScaler: scaleText ? null : TextScaler.noScaling,
          style: textStyle(fontSize, color),
        ),
      ),
    );
  }
}

/// Símbolo aprovado, sem letreiro, com o selo discreto da casa.
class PartnerMark extends StatelessWidget {
  const PartnerMark({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ScapeMatch Parceiro',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScapeLogo(variant: ScapeLogoVariant.mark, height: height),
          SizedBox(width: height * 0.16),
          PartnerSeal(
            key: PartnerSeal.markKey,
            fontSize: height * PartnerSeal._markFontFactor,
          ),
        ],
      ),
    );
  }
}

/// Lockup pin + ScapeMatch com o selo centrado embaixo.
class PartnerLockup extends StatelessWidget {
  const PartnerLockup({super.key, this.height = 64});

  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var logoHeight = height;
        final maxW = constraints.maxWidth;
        if (maxW.isFinite && maxW > 0) {
          final natural = ScapeLogo.lockupWidthFor(context, logoHeight);
          if (natural > maxW && natural > 0) {
            logoHeight *= maxW / natural;
          }
        }
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Semantics(
          label: 'ScapeMatch Parceiro',
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScapeLogo(height: logoHeight),
                SizedBox(height: PartnerSeal.gapFor(logoHeight)),
                PartnerSeal(
                  key: PartnerSeal.lockupKey,
                  fontSize: PartnerSeal.fontFor(logoHeight),
                  solidPeach: dark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Selo da abertura. Fica parado sob o lockup.
///
/// Enquanto o letreiro entra no pin, o selo se desfaz da esquerda para a
/// direita, em brilho, e some antes do giro. Com menos movimento, [fade]
/// apaga o selo inteiro, sem varredura e sem faísca.
class PartnerSealTrain extends StatelessWidget {
  const PartnerSealTrain({
    super.key,
    required this.logoHeight,
    required this.absorb,
    this.fade = 0,
    this.solidPeach = false,
  });

  final double logoHeight;

  /// 0 no quadro parado. 1 quando o letreiro já entrou no pin.
  final double absorb;

  /// Sumiço simples do reduced motion, de 0 a 1.
  final double fade;
  final bool solidPeach;

  static const slotKey = Key('partner-seal-train-slot');
  static const fadeKey = Key('partner-seal-fade');

  static double extentFor(BuildContext context, double logoHeight) {
    final font = MediaQuery.textScalerOf(context)
        .scale(PartnerSeal.fontFor(logoHeight));
    return PartnerSeal.gapFor(logoHeight) +
        PartnerSeal.pillHeight(context, font, scaleText: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = ScapeLogo.lockupWidthFor(context, logoHeight);
    final font = MediaQuery.textScalerOf(context)
        .scale(PartnerSeal.fontFor(logoHeight));
    final pillH = PartnerSeal.pillHeight(context, font, scaleText: false);
    final tucked = absorb.clamp(0.0, 1.0);
    final faded = fade.clamp(0.0, 1.0);
    final seal = PartnerSeal(
      key: PartnerSeal.splashKey,
      fontSize: font,
      solidPeach: solidPeach,
      scaleText: false,
    );
    final Widget body;
    if (faded > 0) {
      body = Opacity(key: fadeKey, opacity: 1 - faded, child: seal);
    } else if (tucked <= 0) {
      body = seal;
    } else if (tucked >= 1) {
      body = SizedBox(height: pillH);
    } else {
      body = PartnerSealDissolve(progress: tucked, child: seal);
    }
    return SizedBox(
      key: slotKey,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: PartnerSeal.gapFor(logoHeight)),
          Align(alignment: Alignment.topCenter, child: body),
        ],
      ),
    );
  }
}

/// Varredura do selo. À esquerda do corte não resta pílula: o pedaço
/// acende numa faixa estreita e vira faísca. Sem gradiente largo nem blur.
class PartnerSealDissolve extends StatelessWidget {
  const PartnerSealDissolve({
    super.key,
    required this.progress,
    required this.child,
  });

  static const dissolveKey = Key('partner-seal-dissolve');
  static const sparksKey = Key('partner-seal-sparks');

  /// Faixa, em px, onde a frente e as faíscas podem pintar.
  /// À esquerda disso o fundo fica intacto.
  static const frontBand = 6.0;

  /// 0 é o selo inteiro. 1 já o apagou.
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return Stack(
      key: dissolveKey,
      alignment: Alignment.center,
      children: [
        ClipRect(
          clipper: _KeepRightClipper(progress: p),
          clipBehavior: Clip.hardEdge,
          child: child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: sparksKey,
              painter: _SealSparkPainter(progress: p),
            ),
          ),
        ),
      ],
    );
  }
}

/// Corta o selo no pixel do corte. Não deixa alpha parcial à esquerda.
class _KeepRightClipper extends CustomClipper<Rect> {
  const _KeepRightClipper({required this.progress});

  final double progress;

  @override
  Rect getClip(Size size) {
    final edge = size.width * progress;
    return Rect.fromLTRB(edge, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _KeepRightClipper oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _SealSparkPainter extends CustomPainter {
  const _SealSparkPainter({required this.progress});

  final double progress;

  static const _copper = Color(0xFFD2642A);
  static const _ember = Color(0xFFFFB27A);
  static const _light = Color(0xFFFFF6EA);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final edge = size.width * progress;
    // Faixa de 3px, só no que ainda resta, encostada no corte.
    canvas.drawRect(
      Rect.fromLTWH(edge, 0, 3, size.height),
      Paint()
        ..color = _light
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      Rect.fromLTWH(edge + 2, 0, 1.5, size.height),
      Paint()
        ..color = _ember
        ..isAntiAlias = false,
    );

    const count = 11;
    for (var i = 0; i < count; i++) {
      final n = i + 1;
      final y = (0.16 + ((n * 37) % 68) / 100) * size.height;
      // Cabe na faixa de [PartnerSealDissolve.frontBand] à esquerda do corte.
      final dx = ((n % 4) - 2) * 1.2;
      final color = switch (n % 3) {
        0 => _light,
        1 => _ember,
        _ => _copper,
      };
      canvas.drawCircle(
        Offset(edge + dx, y),
        1.0 + (n % 3) * 0.35,
        Paint()
          ..color = color
          ..isAntiAlias = false,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SealSparkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
