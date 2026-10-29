import 'package:flutter/foundation.dart';
import 'package:scapematch/core/sharing/web_base.dart';

/// Link público de um grupo.
///
/// Fora da web é a rota go_router `/convite/:id`. Na web é a URL absoluta
/// com o `<base href>` (no GitHub Pages, `/scapematch/`), sem a rota que
/// estiver aberta.
String groupLink(String groupId, {Uri? page, bool? onWeb, String? baseHref}) {
  final route = '/convite/$groupId';
  final web = onWeb ?? kIsWeb;
  if (!web) {
    return route;
  }
  final current = page ?? Uri.base;
  final prefix = _deploymentPrefix(baseHref ?? webBaseHref());
  final path = prefix.isEmpty ? route : '$prefix$route';
  return Uri(
    scheme: current.scheme,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: path,
  ).toString();
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
