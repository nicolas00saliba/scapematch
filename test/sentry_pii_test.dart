import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/observability/pii.dart';
import 'package:scapematch/core/observability/sentry_boot.dart';

void main() {
  test('redige e-mail, CPF e telefone e preserva o resto', () {
    const texto =
        'Conta ana.silva@escapematch.com.br CPF 123.456.789-09 '
        'fone (41) 98888-7777 e +55 11 3333-4444. Pedido 42.';

    final saida = redigirPii(texto);

    expect(saida.contains('ana.silva'), isFalse);
    expect(saida.contains('123.456.789-09'), isFalse);
    expect(saida.contains('98888-7777'), isFalse);
    expect(saida.contains('3333-4444'), isFalse);
    expect(saida, contains('[email]'));
    expect(saida, contains('[cpf]'));
    expect(saida, contains('[telefone]'));
    expect(saida, contains('Pedido 42'));
  });

  test('redige parâmetro de URL e onze dígitos soltos', () {
    expect(
      redigirPii('https://app.escapematch.com.br/login?email=ana@casa.com'),
      'https://app.escapematch.com.br/login?email=[redigido]',
    );
    expect(redigirPii('celular 41988887777'), 'celular [telefone]');
    expect(redigirPii('doc 12345678909'), 'doc [cpf]');
  });

  test('DSN vazio ou sem https não liga o SDK', () {
    expect(dsnValido(''), isFalse);
    expect(dsnValido('http://publico@ingest.exemplo.invalid/1'), isFalse);
    expect(dsnValido('https://ingest.exemplo.invalid/1'), isFalse);
    expect(dsnValido('https://publico@ingest.exemplo.invalid/1'), isTrue);
  });

  test('redige tokens na query, no fragmento, no request e no breadcrumb', () {
    expect(
      redigirPii(
        'https://app.escapematch.com.br/auth?code=pkce&token=xyz'
        '#access_token=aaa&refresh_token=bbb&type=recovery'
        '&provider_token=ccc&id_token=ddd&token_type=bearer',
      ),
      'https://app.escapematch.com.br/auth?code=[redigido]&token=[redigido]'
      '#access_token=[redigido]&refresh_token=[redigido]&type=[redigido]'
      '&provider_token=[redigido]&id_token=[redigido]&token_type=[redigido]',
    );
    expect(
      redigirPii('access_token=aaa&refresh_token=bbb'),
      'access_token=[redigido]&refresh_token=[redigido]',
    );
    expect(
      redigirPii('https://escapematch.com.br/ajuda?tema=pagamento'),
      'https://escapematch.com.br/ajuda?tema=pagamento',
    );

    final request = redigirValor({
      'url': 'https://app.escapematch.com.br/auth?code=abc#access_token=zzz',
      'query_string': 'code=abc&type=signup',
      'fragment': 'access_token=zzz&refresh_token=yyy&provider_refresh_token=qqq',
    });
    expect(request, {
      'url':
          'https://app.escapematch.com.br/auth?code=[redigido]#access_token=[redigido]',
      'query_string': 'code=[redigido]&type=[redigido]',
      'fragment':
          'access_token=[redigido]&refresh_token=[redigido]&provider_refresh_token=[redigido]',
    });

    final navegacao = redigirValor({
      'category': 'navigation',
      'data': {
        'from': 'https://app.escapematch.com.br/#access_token=segredo',
        'to': 'https://app.escapematch.com.br/login?code=abc',
      },
    });
    expect(navegacao, {
      'category': 'navigation',
      'data': {
        'from': 'https://app.escapematch.com.br/#access_token=[redigido]',
        'to': 'https://app.escapematch.com.br/login?code=[redigido]',
      },
    });

    final fetch = redigirValor({
      'category': 'fetch',
      'data': {
        'url': 'https://api.exemplo/rest?token=abc&provider_token=def',
      },
    });
    expect(fetch, {
      'category': 'fetch',
      'data': {
        'url':
            'https://api.exemplo/rest?token=[redigido]&provider_token=[redigido]',
      },
    });
  });

  test('todo erro é enviado e o traço fica em 5%', () {
    expect(taxaAmostragemErros, 1);
    expect(taxaAmostragemTraces, 0.05);
  });

  test('remove chaves de contato de um mapa', () {
    final saida = redigirValor({
      'email': 'ana@casa.com',
      'caminho': 'login de ana@casa.com',
      'passo': 2,
    });

    expect(saida, {'caminho': 'login de [email]', 'passo': 2});
  });
}
