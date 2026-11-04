import 'dart:typed_data';

import 'save_bytes_stub.dart' if (dart.library.html) 'save_bytes_web.dart';

/// Grava um arquivo no aparelho. Na web, dispara o download. No teste, devolve falso.
Future<bool> saveBytes({
  required String filename,
  required List<int> bytes,
  required String mime,
}) {
  return saveBytesImpl(
    filename: filename,
    bytes: Uint8List.fromList(bytes),
    mime: mime,
  );
}
