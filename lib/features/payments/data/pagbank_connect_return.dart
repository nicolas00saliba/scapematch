/// Retorno do PagBank Connect. A URL cadastrada termina em `/pagbank/retorno`.
class PagbankConnectReturn {
  const PagbankConnectReturn({required this.code, required this.state});

  final String code;
  final String state;

  static PagbankConnectReturn? fromUri(Uri uri) {
    final path = uri.path;
    if (path != '/pagbank/retorno' && !path.endsWith('/pagbank/retorno')) {
      return null;
    }
    final code = uri.queryParameters['code']?.trim() ?? '';
    final state = uri.queryParameters['state']?.trim() ?? '';
    if (code.isEmpty || state.isEmpty) return null;
    return PagbankConnectReturn(code: code, state: state);
  }
}

/// Lido no boot, antes da troca de estratégia de URL. Some quando a tela abre.
PagbankConnectReturn? pendingPagbankConnectReturn;
