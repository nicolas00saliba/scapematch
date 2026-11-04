import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('document')
external JSObject get _document;

@JS('URL')
external JSObject get _url;

@JS('Blob')
external JSFunction get _blob;

Future<bool> saveBytesImpl({
  required String filename,
  required Uint8List bytes,
  required String mime,
}) async {
  try {
    final blob = _blob.callAsConstructor(
      [bytes.toJS].toJS,
      {'type': mime}.jsify(),
    );
    final href = (_url['createObjectURL'] as JSFunction).callAsFunction(
      _url,
      blob,
    ) as JSString;
    final anchor =
        (_document['createElement'] as JSFunction).callAsFunction(
              _document,
              'a'.toJS,
            )
            as JSObject;
    anchor['href'] = href;
    anchor['download'] = filename.toJS;
    (anchor['click'] as JSFunction).callAsFunction(anchor);
    (_url['revokeObjectURL'] as JSFunction).callAsFunction(_url, href);
    return true;
  } catch (_) {
    return false;
  }
}
