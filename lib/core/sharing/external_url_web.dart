import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:scapematch/core/sharing/external_url_launch.dart';

@JS('window')
external JSObject get _window;

/// Nova aba na web. O mesmo helper no celular abre o app do link.
Future<bool> openExternalUrl(Uri uri) => launchExternalUrl(uri);

/// Web Share API. Se o navegador não tiver, devolve falso.
Future<bool> sharePlainText(String text) async {
  try {
    final nav = _window['navigator'] as JSObject?;
    final share = nav?['share'];
    if (nav == null || share == null) {
      return false;
    }
    final data = {'title': 'ScapeMatch', 'text': text}.jsify();
    final result = (share as JSFunction).callAsFunction(nav, data);
    if (result != null && result.isA<JSPromise>()) {
      await (result as JSPromise).toDart;
    }
    return true;
  } catch (_) {
    return false;
  }
}
