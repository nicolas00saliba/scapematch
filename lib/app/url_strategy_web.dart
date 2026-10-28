import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Path na barra de endereço, sem `#`. O GitHub Pages já serve o
/// `index.html` como `404.html`, então `/scapematch/convite/:id` abre o app.
void configureUrlStrategy() {
  usePathUrlStrategy();
}
