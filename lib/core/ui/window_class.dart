import 'package:flutter/widgets.dart';

/// A partir daqui o ScapeMatch vira site: navegação no topo e conteúdo largo.
/// Abaixo disso continua o app de celular, com a barra embaixo.
const scapeDesktopMinWidth = 960.0;

bool isScapeDesktop(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= scapeDesktopMinWidth;
}
