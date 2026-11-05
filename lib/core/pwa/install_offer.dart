/// O que o aviso de instalação pode oferecer neste aparelho.
enum InstallOffer {
  /// Chrome/Android: o toque chama `beforeinstallprompt`.
  prompt,

  /// iPhone/Safari: não há prompt. O texto explica o caminho.
  instructions,
}

/// Sinais lidos do navegador. O widget de teste monta os seus.
class InstallSignals {
  const InstallSignals({
    required this.standalone,
    required this.ios,
    required this.promptReady,
    required this.dismissed,
  });

  final bool standalone;
  final bool ios;
  final bool promptReady;
  final bool dismissed;
}

/// Nulo quando o aviso não deve aparecer.
///
/// Some no app já instalado (`display-mode: standalone`) e depois que
/// a pessoa fecha. O prompt do Chrome ganha do texto do iPhone.
InstallOffer? installOfferFor({
  required bool enabled,
  required bool standalone,
  required bool dismissed,
  required bool ios,
  required bool promptReady,
}) {
  if (!enabled || standalone || dismissed) return null;
  if (promptReady) return InstallOffer.prompt;
  if (ios) return InstallOffer.instructions;
  return null;
}
