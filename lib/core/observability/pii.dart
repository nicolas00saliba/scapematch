/// Tira e-mail, CPF e telefone de textos que podem ir para o Sentry.
///
/// O DSN não entra aqui. Sem DSN no build, o SDK nem chega a ser iniciado.
String redigirPii(String texto) {
  var saida = texto;
  saida = saida.replaceAll(_email, '[email]');
  saida = saida.replaceAllMapped(_parametroSensivel, (match) {
    return '${match.group(1)}[redigido]';
  });
  saida = saida.replaceAll(_cpfFormatado, '[cpf]');
  saida = saida.replaceAll(_telefoneFormatado, '[telefone]');
  saida = saida.replaceAllMapped(_onzeDigitos, (match) {
    final digitos = match.group(0)!;
    final terceiro = digitos[2];
    return terceiro == '9' ? '[telefone]' : '[cpf]';
  });
  return saida;
}

/// DSN público do Sentry. Vazio ou malformado deixa o SDK inerte.
bool dsnValido(String dsn) {
  if (dsn.isEmpty || dsn.contains(RegExp(r'\s'))) {
    return false;
  }
  final uri = Uri.tryParse(dsn);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return false;
  }
  if (uri.userInfo.isEmpty || uri.pathSegments.isEmpty) {
    return false;
  }
  return uri.pathSegments.last.isNotEmpty;
}

Object? redigirValor(Object? valor) {
  if (valor is String) {
    return redigirPii(valor);
  }
  if (valor is Map) {
    final saida = <String, Object?>{};
    valor.forEach((chave, item) {
      final nome = chave.toString();
      if (_chavesSensiveis.contains(nome)) {
        return;
      }
      saida[nome] = redigirValor(item);
    });
    return saida;
  }
  if (valor is List) {
    return [for (final item in valor) redigirValor(item)];
  }
  return valor;
}

const _chavesSensiveis = {
  'email',
  'ip_address',
  'ipAddress',
  'phone',
  'telefone',
  'cpf',
  'cookies',
};

final _email = RegExp(
  r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
  caseSensitive: false,
);

final _parametroSensivel = RegExp(
  r'([?&](?:email|e-mail|cpf|telefone|phone|celular)=)[^&#\s]+',
  caseSensitive: false,
);

final _cpfFormatado = RegExp(r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b');

final _telefoneFormatado = RegExp(
  r'(?:\+?55\s*)?\(?\d{2}\)?\s*9?\d{4}[-\s]\d{4}\b',
);

final _onzeDigitos = RegExp(r'\b\d{11}\b');
