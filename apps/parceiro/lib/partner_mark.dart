import 'dart:math' as math;

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

/// Selo da abertura. No quadro parado fica centrado sob o lockup.
/// No trem, desliza a mesma distância do letreiro e some na ponta do pin,
/// sem a folga transparente da caixa.
class PartnerSealTrain extends StatelessWidget {
  const PartnerSealTrain({
    super.key,
    required this.logoHeight,
    required this.absorb,
    this.solidPeach = false,
  });

  final double logoHeight;
  final double absorb;
  final bool solidPeach;

  static const slotKey = Key('partner-seal-train-slot');
  static const trainKey = Key('partner-seal-train');

  static double extentFor(BuildContext context, double logoHeight) {
    final font = MediaQuery.textScalerOf(context)
        .scale(PartnerSeal.fontFor(logoHeight));
    return PartnerSeal.gapFor(logoHeight) +
        PartnerSeal.pillHeight(context, font, scaleText: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = ScapeLogo.lockupWidthFor(context, logoHeight);
    final pinW = ScapeLogo.pinWidthFor(logoHeight);
    final lane = math.max(0.0, width - pinW);
    final font = MediaQuery.textScalerOf(context)
        .scale(PartnerSeal.fontFor(logoHeight));
    final pillH = PartnerSeal.pillHeight(context, font, scaleText: false);
    final tucked = absorb.clamp(0.0, 1.0);
    final Widget pill = tucked >= 1
        ? SizedBox(width: width, height: pillH)
        : Align(
            alignment: Alignment.topCenter,
            child: PartnerSeal(
              key: PartnerSeal.splashKey,
              fontSize: font,
              solidPeach: solidPeach,
              scaleText: false,
            ),
          );
    Widget train = Transform.translate(
      key: trainKey,
      offset: Offset(-tucked * lane, 0),
      child: pill,
    );
    if (tucked > 0 && tucked < 1) {
      train = ClipPath(
        clipBehavior: Clip.hardEdge,
        clipper: _SealIntoPinClipper(edge: pinW / 2 + _SealIntoPinClipper.tuck),
        child: train,
      );
    }
    return SizedBox(
      key: slotKey,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: PartnerSeal.gapFor(logoHeight)),
          train,
        ],
      ),
    );
  }
}

/// Fecha o que já passou da ponta do pin. A caixa do PNG é mais larga que
/// o corpo; cortar nela deixaria um halo antes do pin.
class _SealIntoPinClipper extends CustomClipper<Path> {
  const _SealIntoPinClipper({required this.edge});

  final double edge;

  static const tuck = 1.0;

  @override
  Path getClip(Size size) {
    final left = edge.clamp(0.0, size.width);
    return Path()..addRect(Rect.fromLTRB(left, 0, size.width, size.height));
  }

  @override
  bool shouldReclip(covariant _SealIntoPinClipper oldDelegate) {
    return oldDelegate.edge != edge;
  }
}
