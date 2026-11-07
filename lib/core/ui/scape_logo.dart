import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.markImage,
  });

  final ScapeLogoVariant variant;
  final double height;

  /// Versão clara, para foto escura. Nulo segue o tema.
  final bool? onDark;
  final VoidCallback? onTap;

  /// 0 deixa o letreiro ao lado do símbolo. 1 já o enfiou no pin.
  /// No meio, o letreiro desliza para a esquerda e some na silhueta verde,
  /// como um trem entrando. A folga transparente do viewBox não corta as
  /// letras. O pin não muda de tamanho nem de proporção.
  final double wordmarkAbsorb;

  /// Pin em arquivo, no lugar do SVG. O Parceiro usa o logo com fundo
  /// preto. Nulo mantém o desenho compartilhado do jogador. A caixa
  /// continua [markAspectWidth] por [markAspectHeight].
  final ImageProvider? markImage;

  /// Preto do arquivo do Parceiro. Fecha a folga do encaixe sem pintar branco.
  static const markImageBackground = Color(0xFF111111);

  static const pin = Color(0xFF0F4C4A);
  static const copper = Color(0xFFD2642A);
  static const pinOnDark = Color(0xFFF4F1EA);

  static const markAsset = 'assets/brand/logo_simbolo.svg';
  static const markOnDarkAsset = 'assets/brand/logo_simbolo_claro.svg';

  /// viewBox do símbolo. A largura e a altura do pin usam esta razão:
  /// outra razão estica o disco branco.
  static const markAspectWidth = 200.0;
  static const markAspectHeight = 260.0;

  /// Folga à direita do letreiro para o texto medido não ser cortado.
  static const wordmarkSlack = 16.0;

  static double pinWidthFor(double height) =>
      height * markAspectWidth / markAspectHeight;

  static double wordmarkGapFor(double height) => height * 0.18;

  static double wordmarkWidthFor(BuildContext context, double height) {
    final painter = TextPainter(
      text: TextSpan(text: 'ScapeMatch', style: _Wordmark.styleFor(height)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  /// Largura do pin, do vão e do letreiro. Não muda enquanto o trem entra,
  /// para o pin não saltar no centro da tela.
  static double lockupWidthFor(BuildContext context, double height) {
    return pinWidthFor(height) +
        wordmarkGapFor(height) +
        wordmarkWidthFor(context, height) +
        wordmarkSlack;
  }

  bool _onDark(BuildContext context) {
    return onDark ?? Theme.of(context).brightness == Brightness.dark;
  }

  Widget _pin(bool dark) {
    final width = pinWidthFor(height);
    final image = markImage;
    if (image != null) {
      return ColoredBox(
        color: markImageBackground,
        child: Image(
          image: image,
          height: height,
          width: width,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      );
    }
    return SvgPicture(
      ScapePinLoader(dark ? markOnDarkAsset : markAsset),
      height: height,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      excludeFromSemantics: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _onDark(context);
    final logo = variant == ScapeLogoVariant.mark
        ? _pin(dark)
        : _fullLogo(context, dark);
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

  Widget _fullLogo(BuildContext context, bool dark) {
    final pinW = pinWidthFor(height);
    final width = lockupWidthFor(context, height);
    final gap = wordmarkGapFor(height);
    final absorb = wordmarkAbsorb.clamp(0.0, 1.0);
    final lane = width - pinW;
    final train = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: gap),
        _Wordmark(height: height, onDark: dark),
      ],
    );
    // A caixa não encolhe: o pin fica no lugar. O letreiro passa por baixo
    // do SVG, então some nos pixels verdes e não na folga do viewBox.
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (absorb <= 0)
            Positioned(
              left: pinW,
              top: 0,
              width: lane,
              height: height,
              child: Align(alignment: Alignment.centerLeft, child: train),
            )
          else if (absorb < 1)
            Positioned(
              left: 0,
              top: 0,
              width: width,
              height: height,
              child: ClipPath(
                clipper: _WordmarkTrainClipper(
                  pinWidth: pinW,
                  logoHeight: height,
                ),
                child: Transform.translate(
                  offset: Offset(pinW - absorb * lane, 0),
                  child: Align(alignment: Alignment.centerLeft, child: train),
                ),
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            width: pinW,
            height: height,
            child: _pin(dark),
          ),
        ],
      ),
    );
  }
}

/// Esconde o que já passou da silhueta, à esquerda.
///
/// O viewBox é 200×260 e o círculo verde vai de x=10 a x=190 (centro 100,
/// raio 90; o pescoço do path está em y=154 e a ponta em y=250). A faixa
/// entre o verde e a caixa é transparente. Recortar na borda da caixa faz
/// as letras sumirem nessa faixa, que no branco da splash parece um halo.
///
/// O desenho do pin fica por cima e cobre as letras nos pixels opacos.
/// Aqui o recorte só fecha a saída esquerda, para o começo do letreiro não
/// reaparecer na folga transparente do outro lado. Ele entra um pixel no
/// verde para o antialiasing da borda não deixar um fiapo de letra.
class _WordmarkTrainClipper extends CustomClipper<Path> {
  const _WordmarkTrainClipper({
    required this.pinWidth,
    required this.logoHeight,
  });

  final double pinWidth;
  final double logoHeight;

  static const _tuck = 1.0;
  static const _cx = 100.0;
  static const _cy = 100.0;
  static const _radius = 90.0;
  static const _neckY = 154.0;
  static const _neckLeft = 28.0;
  static const _tipY = 250.0;
  static const _tipX = 100.0;

  double _leftEdge(double y) {
    final sx = pinWidth / ScapeLogo.markAspectWidth;
    final sy = logoHeight / ScapeLogo.markAspectHeight;
    final yb = sy == 0 ? 0.0 : y / sy;
    final top = _cy - _radius;
    if (yb <= top || yb >= _tipY) {
      return pinWidth;
    }
    final double xVb;
    if (yb <= _neckY) {
      final dy = yb - _cy;
      final rest = _radius * _radius - dy * dy;
      final dx = rest <= 0 ? 0.0 : math.sqrt(rest);
      xVb = _cx - dx;
    } else {
      final t = (yb - _neckY) / (_tipY - _neckY);
      xVb = _neckLeft + (_tipX - _neckLeft) * t;
    }
    return xVb * sx + _tuck;
  }

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(size.width, 0);
    const samples = 96;
    for (var i = 0; i <= samples; i++) {
      final y = size.height * i / samples;
      path.lineTo(_leftEdge(y), y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _WordmarkTrainClipper oldDelegate) {
    return oldDelegate.pinWidth != pinWidth ||
        oldDelegate.logoHeight != logoHeight;
  }
}

/// Abre o SVG do pin no jogador e no Parceiro.
///
/// O jogador é o próprio pacote `scapematch`. O bundle dele registra
/// `assets/brand/logo_simbolo.svg` (e o claro). O Parceiro depende do
/// pacote, então o mesmo arquivo entra como
/// `packages/scapematch/assets/brand/...`.
///
/// `SvgPicture.asset(..., package: 'scapematch')` pede sempre a chave com
/// prefixo. No bundle do jogador — inclusive no build web — essa chave não
/// existe: o SVG não pinta e sobra o letreiro, que é texto. A caixa do pin
/// continua no [Stack]; o buraco é o desenho que não carregou.
///
/// A chave do pacote vem primeiro para o Parceiro usar o arquivo
/// compartilhado, mesmo tendo uma cópia em `assets/brand/`. Sem essa chave,
/// vale a do app, que é o caso do jogador.
class ScapePinLoader extends SvgAssetLoader {
  const ScapePinLoader(super.assetName, {super.assetBundle});

  static const sharedPackage = 'scapematch';

  static String packagedKey(String assetName) =>
      'packages/$sharedPackage/$assetName';

  @override
  Future<ByteData?> prepareMessage(BuildContext? context) async {
    final bundle = _bundle(context);
    final packaged = packagedKey(assetName);
    if (await _has(bundle, packaged)) {
      return bundle.load(packaged);
    }
    return bundle.load(assetName);
  }

  /// Bytes do SVG na chave que este bundle realmente tem.
  @visibleForTesting
  Future<ByteData> readSvg() async {
    final bytes = await prepareMessage(null);
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $assetName');
    }
    return bytes;
  }

  AssetBundle _bundle(BuildContext? context) {
    if (assetBundle != null) {
      return assetBundle!;
    }
    if (context != null) {
      return DefaultAssetBundle.of(context);
    }
    return rootBundle;
  }

  static Future<bool> _has(AssetBundle bundle, String key) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      return manifest.getAssetVariants(key) != null;
    } on Object {
      try {
        await bundle.load(key);
        return true;
      } on FlutterError {
        return false;
      }
    }
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.height, required this.onDark});

  final double height;
  final bool onDark;

  static TextStyle styleFor(double height) {
    final size = height * 0.52;
    // O SVG usa letter-spacing -1 em 128px.
    return TextStyle(
      fontFamily: 'Poppins',
      fontWeight: FontWeight.w500,
      fontSize: size,
      letterSpacing: size * -1 / 128,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: height * 0.08),
      child: Text.rich(
        TextSpan(
          style: styleFor(height),
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
