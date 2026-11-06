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
  });

  final ScapeLogoVariant variant;
  final double height;

  /// Versão clara, para foto escura. Nulo segue o tema.
  final bool? onDark;
  final VoidCallback? onTap;

  /// 0 deixa o letreiro ao lado do símbolo. 1 já o enfiou no pin.
  /// No meio, o letreiro desliza para a esquerda e some na borda do pin,
  /// como um trem entrando. O pin não muda de tamanho nem de proporção.
  final double wordmarkAbsorb;

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
    return SvgPicture(
      ScapePinLoader(dark ? markOnDarkAsset : markAsset),
      height: height,
      width: pinWidthFor(height),
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
    // A caixa não encolhe: o pin fica no lugar. O letreiro só é cortado
    // depois que atravessa a borda direita do pin.
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: pinW,
            height: height,
            child: _pin(dark),
          ),
          if (absorb < 1)
            Positioned(
              left: pinW,
              top: 0,
              width: lane,
              height: height,
              child: absorb <= 0
                  ? Align(alignment: Alignment.centerLeft, child: train)
                  : ClipRect(
                      child: Transform.translate(
                        offset: Offset(-absorb * lane, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: train,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
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
