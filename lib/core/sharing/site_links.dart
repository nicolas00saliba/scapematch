import 'package:scapematch/core/sharing/web_base.dart';

/// App da casa, publicado ao lado do jogador.
///
/// No Pages o jogador fica em `/scapematch/` e a casa em
/// `/scapematch/parceiro/`. O caminho é absoluto de propósito: o `<base href>`
/// do jogador não pode puxar esse link para dentro do próprio app.
Uri partnerAppUri({Uri? page}) {
  final current = page ?? Uri.base;
  const path = '/scapematch/parceiro/';
  if (current.host.isEmpty) {
    return Uri(path: path);
  }
  return Uri(
    scheme: current.scheme.isEmpty ? 'https' : current.scheme,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: path,
  );
}

/// Página do jogador, para colar num convite.
String playerHomeLink({Uri? page, String? baseHref}) {
  final current = page ?? Uri.base;
  final prefix = _deploymentPrefix(baseHref ?? webBaseHref());
  final path = prefix.isEmpty ? '/' : '$prefix/';
  if (current.host.isEmpty) {
    return path;
  }
  return Uri(
    scheme: current.scheme.isEmpty ? 'https' : current.scheme,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: path,
  ).toString();
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
