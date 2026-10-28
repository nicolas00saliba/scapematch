import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

/// `window.open` para o WhatsApp.
Future<bool> openExternalUrl(Uri uri) async {
  try {
    final open = _window['open'];
    if (open == null) {
      return false;
    }
    (open as JSFunction).callAsFunction(
      _window,
      uri.toString().toJS,
      '_blank'.toJS,
    );
    return true;
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
