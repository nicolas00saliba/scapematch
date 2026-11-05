import 'package:scapematch/core/sharing/public_origins.dart';
import 'package:scapematch/core/sharing/web_base.dart';

/// App da casa.
///
/// Em produção o Parceiro mora em [partnerAppOrigin]. No GitHub Pages antigo
/// ele ainda fica em [legacyPartnerPath] no mesmo host. Fora da web, o
/// caminho relativo aponta o Pages antigo para quem cola o link à mão.
Uri partnerAppUri({Uri? page}) {
  final current = page ?? Uri.base;
  if (current.host == legacyPagesHost) {
    return Uri(
      scheme: current.scheme.isEmpty ? 'https' : current.scheme,
      host: current.host,
      port: current.hasPort ? current.port : null,
      path: legacyPartnerPath,
    );
  }
  if (current.host.isEmpty) {
    return Uri(path: legacyPartnerPath);
  }
  return Uri.parse('$partnerAppOrigin/');
}

/// Página do jogador, para colar num convite.
String playerHomeLink({Uri? page, String? baseHref}) {
  final current = page ?? Uri.base;
  final prefix = _deploymentPrefix(baseHref ?? webBaseHref());
  final path = prefix.isEmpty ? '/' : '$prefix/';
  if (current.host == legacyPagesHost) {
    final legacyPath = prefix.isEmpty ? legacyPlayerPath : '$prefix/';
    return Uri(
      scheme: current.scheme.isEmpty ? 'https' : current.scheme,
      host: current.host,
      port: current.hasPort ? current.port : null,
      path: legacyPath,
    ).toString();
  }
  if (current.host.isEmpty) {
    return path;
  }
  // Nos hosts do produto (app/demo) usa o host atual + base do build.
  if (current.host == 'app.scapematch.com.br' ||
      current.host == 'demo.scapematch.com.br') {
    return Uri(
      scheme: current.scheme.isEmpty ? 'https' : current.scheme,
      host: current.host,
      port: current.hasPort ? current.port : null,
      path: path,
    ).toString();
  }
  return '$playerAppOrigin/';
}

/// Texto para mandar o ScapeMatch a alguém que ainda não tem o app.
String friendInviteText({Uri? page, String? baseHref}) {
  final link = playerHomeLink(page: page, baseHref: baseHref);
  return 'Vem jogar no ScapeMatch comigo. '
      'A gente monta o grupo e divide a sala.\n'
      '$link';
}

/// `/` e `/scapematch/` viram vazio e `/scapematch`.
String _deploymentPrefix(String href) {
  final parsed = href.contains('://') ? Uri.parse(href) : null;
  var path = parsed?.path ?? href;
  if (path.isEmpty || path == '/') {
    return '';
  }
  if (!path.startsWith('/')) {
    path = '/$path';
  }
  while (path.endsWith('/') && path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  return path == '/' ? '' : path;
}
