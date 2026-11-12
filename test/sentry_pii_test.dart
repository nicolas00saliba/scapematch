import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/observability/pii.dart';

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

  test('remove chaves de contato de um mapa', () {
    final saida = redigirValor({
      'email': 'ana@casa.com',
      'caminho': 'login de ana@casa.com',
      'passo': 2,
    });

    expect(saida, {'caminho': 'login de [email]', 'passo': 2});
  });
}
