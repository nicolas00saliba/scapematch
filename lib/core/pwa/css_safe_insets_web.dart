import 'package:flutter/painting.dart';
import 'package:web/web.dart';

/// Mede o recuo que o navegador reserva para o notch e o indicador.
///
/// O Flutter 3.47 não lê esses valores. Um elemento sonda recebe
/// `env(safe-area-inset-*)` e o estilo calculado devolve pixels.
EdgeInsets readCssSafeAreaInsets() {
  final body = document.body;
  if (body == null) return EdgeInsets.zero;
  final probe = HTMLDivElement()
    ..style.position = 'absolute'
    ..style.visibility = 'hidden'
    ..style.pointerEvents = 'none'
    ..style.paddingTop = 'env(safe-area-inset-top, 0px)'
    ..style.paddingRight = 'env(safe-area-inset-right, 0px)'
    ..style.paddingBottom = 'env(safe-area-inset-bottom, 0px)'
    ..style.paddingLeft = 'env(safe-area-inset-left, 0px)';
  body.appendChild(probe);
  final style = window.getComputedStyle(probe);
  final insets = EdgeInsets.fromLTRB(
    _px(style.paddingLeft),
    _px(style.paddingTop),
    _px(style.paddingRight),
    _px(style.paddingBottom),
  );
  probe.remove();
  return insets;
}

double _px(String value) {
  if (value.isEmpty) return 0;
  return double.tryParse(value.replaceAll('px', '').trim()) ?? 0;
}
