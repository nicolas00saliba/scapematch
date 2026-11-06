import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Marca aprovada em 2026-11-03.
///
/// [ScapeLogoVariant.full] é o símbolo mais o letreiro. Cabe no topo largo
/// e na introdução. [ScapeLogoVariant.mark] é só o pin, para a barra do
/// celular, o favicon e os ícones. O app da casa usa o pin com um selo.
///
/// O SVG completo escreve o letreiro com a fonte Poppins. O widget desenha
/// essas letras aqui, em Poppins 500, para o texto não depender da fonte
/// instalada no aparelho. O desenho do pin continua o do arquivo.
enum ScapeLogoVariant { full, mark }

/// A partir desta largura o topo mostra o logo completo.
const scapeWideLogoWidth = 960.0;

class ScapeLogo extends StatelessWidget {
  const ScapeLogo({
    super.key,
    this.variant = ScapeLogoVariant.full,
    this.height = 40,
    this.onDark,
    this.onTap,
    this.wordmarkAbsorb = 0,
  });

  final ScapeLogoVariant variant;
  final double height;

  /// Versão clara, para foto escura. Nulo segue o tema.
  final bool? onDark;
  final VoidCallback? onTap;

  /// 0 deixa o letreiro ao lado do símbolo. 1 enfia o letreiro nele.
  /// A splash do celular usa isso; o resto do app passa 0.
  final double wordmarkAbsorb;

  static const pin = Color(0xFF0F4C4A);
  static const copper = Color(0xFFD2642A);
  static const pinOnDark = Color(0xFFF4F1EA);

  static const markAsset = 'assets/brand/logo_simbolo.svg';
  static const markOnDarkAsset = 'assets/brand/logo_simbolo_claro.svg';

  bool _onDark(BuildContext context) {
    return onDark ?? Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final dark = _onDark(context);
    final mark = SvgPicture.asset(
      dark ? markOnDarkAsset : markAsset,
      height: height,
      width: height * 200 / 260,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final logo = variant == ScapeLogoVariant.mark
        ? mark
        : _fullLogo(mark, dark);
    final labeled = Semantics(
      label: variant == ScapeLogoVariant.mark ? 'ScapeMatch' : null,
      child: logo,
    );
    if (onTap == null) {
      return labeled;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: labeled,
      ),
    );
  }

  Widget _fullLogo(Widget mark, bool dark) {
    final gap = height * 0.18;
    final wordmark = _Wordmark(height: height, onDark: dark);
    if (wordmarkAbsorb <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mark,
          SizedBox(width: gap),
          wordmark,
        ],
      );
    }
    if (wordmarkAbsorb >= 1) {
      return mark;
    }
    final absorb = wordmarkAbsorb.clamp(0.0, 1.0);
    final remain = 1 - absorb;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        Align(
          alignment: Alignment.centerLeft,
          widthFactor: remain,
          child: Opacity(
            opacity: remain,
            child: Transform.translate(
              offset: Offset(-height * 0.62 * absorb, -height * 0.04 * absorb),
              child: Transform.scale(
                alignment: Alignment.centerLeft,
                scale: 0.05 + 0.95 * remain,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: gap),
                    wordmark,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.height, required this.onDark});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final size = height * 0.52;
    // O SVG usa letter-spacing -1 em 128px.
    final tracking = size * -1 / 128;
    return Padding(
      padding: EdgeInsets.only(bottom: height * 0.08),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: size,
            letterSpacing: tracking,
            height: 1,
          ),
          children: [
            TextSpan(
              text: 'Scape',
              style: TextStyle(
                color: onDark ? ScapeLogo.pinOnDark : ScapeLogo.pin,
              ),
            ),
            const TextSpan(
              text: 'Match',
              style: TextStyle(color: ScapeLogo.copper),
            ),
          ],
        ),
      ),
    );
  }
}
