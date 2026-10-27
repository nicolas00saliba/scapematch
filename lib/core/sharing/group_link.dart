import 'package:flutter/foundation.dart';

/// Link for one group.
///
/// Off the web this is the go_router path (`/groups/:id`). On the web it is
/// an absolute URL under the page that is open, so a GitHub Pages base path
/// such as `/scapematch/` is kept.
String groupLink(String groupId, {Uri? page, bool? onWeb}) {
  final route = '/groups/$groupId';
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
