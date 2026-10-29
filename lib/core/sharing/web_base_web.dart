import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('document')
external JSObject get _document;

/// Prefixo publicado no `<base href>` (por exemplo `/scapematch/`).
String webBaseHref() {
  try {
    final query = _document['querySelector'];
    if (query == null || !query.isA<JSFunction>()) {
      return '/';
    }
    final element = (query as JSFunction).callAsFunction(
      _document,
      'base'.toJS,
    );
    if (element == null || element.isUndefinedOrNull) {
      return '/';
    }
    final node = element as JSObject;
    final read = node['getAttribute'];
    if (read == null || !read.isA<JSFunction>()) {
      return '/';
    }
    final value = (read as JSFunction).callAsFunction(node, 'href'.toJS);
    final raw = value?.dartify();
    if (raw is! String || raw.isEmpty) {
      return '/';
    }
    return raw;
  } catch (_) {
    return '/';
  }
}
