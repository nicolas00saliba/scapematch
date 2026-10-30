import 'package:url_launcher/url_launcher.dart';

/// Abre o link fora da tela atual.
///
/// Na web, [webOnlyWindowName] `_blank` abre outra aba. No celular,
/// [LaunchMode.externalApplication] abre o app correspondente.
/// No teste não há plugin, então devolve falso.
Future<bool> openExternalUrl(Uri uri) async {
  try {
    return await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    return false;
  }
}

/// Folha de compartilhar do sistema. No teste não existe.
Future<bool> sharePlainText(String text) async => false;
