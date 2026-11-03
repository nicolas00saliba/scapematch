/// Endereço do app do jogador a partir da página do Parceiro.
///
/// `/scapematch/parceiro/` volta para `/scapematch/`. Um servidor local
/// em `/parceiro/` volta para a raiz.
String playerAppUrl(String href) {
  final uri = Uri.parse(href);
  final segments = <String>[
    for (final segment in uri.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (segments.isNotEmpty && segments.last == 'index.html') {
    segments.removeLast();
  }
  if (segments.isNotEmpty && segments.last == 'parceiro') {
    segments.removeLast();
  }
  final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}
