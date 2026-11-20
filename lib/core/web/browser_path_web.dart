import 'package:web/web.dart';

/// Troca o caminho sem recarregar, para o refresh não reusar o `code`.
void replaceBrowserPath(String path) {
  window.history.replaceState(null, '', path);
}
