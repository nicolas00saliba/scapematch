import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/sharing/public_origins.dart';
import 'package:scapematch/core/sharing/web_base.dart';

/// App da casa.
///
/// O Parceiro real mora em [partnerAppOrigin]. A demonstração do jogador
/// aponta para [partnerDemoOrigin], noutro host, para não abrir dentro
/// do PWA da demo. No GitHub Pages antigo o Parceiro continua em
/// [legacyPartnerPath]. Fora da web, o app real ainda usa esse caminho
/// relativo; o build de demonstração usa o host novo.
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
  if (_openPartnerDemo(current)) {
    return Uri.parse('$partnerDemoOrigin/');
  }
  if (current.host.isEmpty) {
    return Uri(path: legacyPartnerPath);
  }
  return Uri.parse('$partnerAppOrigin/');
}

/// A demo do jogador abre a demo da casa. O Pages antigo não entra aqui.
bool _openPartnerDemo(Uri current) {
  if (current.host == 'demo.scapematch.com.br') return true;
  if (kAppMode != AppMode.demo) return false;
  if (current.host == 'app.scapematch.com.br' ||
      current.host == 'parceiro.scapematch.com.br') {
    return false;
  }
  return true;
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
