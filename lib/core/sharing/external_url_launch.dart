import 'package:url_launcher/url_launcher.dart';

/// Abre o link fora da tela atual.
///
/// Na web, [webOnlyWindowName] `_blank` abre outra aba. No celular,
/// [LaunchMode.externalApplication] abre o app correspondente.
/// No teste não há plugin, então devolve falso.
Future<bool> launchExternalUrl(Uri uri) async {
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
