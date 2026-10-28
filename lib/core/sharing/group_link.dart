import 'package:flutter/foundation.dart';

/// Link público de um grupo.
///
/// Fora da web é a rota go_router `/convite/:id`. Na web é uma URL absoluta
/// da página aberta, então o prefixo do GitHub Pages (`/scapematch/`) fica.
String groupLink(String groupId, {Uri? page, bool? onWeb}) {
  final route = '/convite/$groupId';
  final web = onWeb ?? kIsWeb;
  if (!web) {
    return route;
  }
  final current = page ?? Uri.base;
  return current
      .replace(
        path: _joinBasePath(current.path, route),
        query: '',
        fragment: '',
      )
      .toString();
}

String _joinBasePath(String basePath, String route) {
  var prefix = basePath;
  if (prefix.endsWith('index.html')) {
    prefix = prefix.substring(0, prefix.length - 'index.html'.length);
  }
  if (prefix.endsWith('/')) {
    prefix = prefix.substring(0, prefix.length - 1);
  }
  final suffix = route.startsWith('/') ? route : '/$route';
  final joined = '$prefix$suffix';
  return joined.startsWith('/') ? joined : '/$joined';
}
