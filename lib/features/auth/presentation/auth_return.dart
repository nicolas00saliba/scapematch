/// Para onde ir depois de entrar, quando não há convite pendente.
///
/// Só aceita a Conta, Meus grupos e Criar grupo. O resto volta para a Home.
String afterAuthLocation(String? next) {
  if (next == null || next.isEmpty) {
    return '/';
  }
  final uri = Uri.tryParse(next);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
    return '/';
  }
  if (uri.path == '/account' || uri.path == '/groups/mine') {
    if (uri.hasQuery) {
      return '/';
    }
    return uri.path;
  }
  if (uri.path != '/groups/new') {
    return '/';
  }
  final extra = uri.queryParameters.keys.where((key) => key != 'roomId');
  if (extra.isNotEmpty) {
    return '/';
  }
  return uri.toString();
}

/// Login que, ao concluir, volta para [next] se ele for um destino seguro.
String loginLocation(String next) {
  return '/login?next=${Uri.encodeQueryComponent(next)}';
}
