import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:url_launcher/url_launcher.dart';

@JS('window')
external JSObject get _window;

/// Nova aba na web. O mesmo helper no celular abre o app do link.
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
