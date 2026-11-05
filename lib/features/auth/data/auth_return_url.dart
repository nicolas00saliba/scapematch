/// URL que o e-mail do Supabase abre.
///
/// É a raiz do app, o mesmo caminho do `start_url` do ícone. Assim o
/// link cai dentro do escopo do PWA e o app instalado abre de novo.
String? authReturnUrl(Uri page, String baseHref) {
  if (!page.hasScheme || page.host.isEmpty) return null;
  final path = directoryPath(baseHref);
  if (path == null) return null;
  return Uri(
    scheme: page.scheme,
    host: page.host,
    port: page.hasPort ? page.port : null,
    path: path,
  ).toString();
}

/// Caminho de diretório do `<base href>`, com barra no começo e no fim.
String? directoryPath(String baseHref) {
  final trimmed = baseHref.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.parse(trimmed);
  var path = parsed.hasScheme ? parsed.path : trimmed;
  final hash = path.indexOf('#');
  if (hash >= 0) path = path.substring(0, hash);
  final query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  if (path.isEmpty) return null;
  if (!path.startsWith('/')) path = '/$path';
  if (!path.endsWith('/')) path = '$path/';
  return path;
}
