import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/auth/data/auth_return_url.dart';

void main() {
  test('o e-mail volta para a raiz que o ícone abre', () {
    final page = Uri.parse(
      'https://nicolas00saliba.github.io/scapematch/cadastro?next=%2Fgroups',
    );
    expect(
      authReturnUrl(page, '/scapematch/'),
      'https://nicolas00saliba.github.io/scapematch/',
    );
    expect(
      authReturnUrl(
        Uri.parse('https://nicolas00saliba.github.io/scapematch/demo/login'),
        '/scapematch/demo/',
      ),
      'https://nicolas00saliba.github.io/scapematch/demo/',
    );
    expect(
      authReturnUrl(
        Uri.parse('https://nicolas00saliba.github.io/scapematch/parceiro/'),
        '/scapematch/parceiro/',
      ),
      'https://nicolas00saliba.github.io/scapematch/parceiro/',
    );
    expect(
      authReturnUrl(
        Uri.parse(
          'https://nicolas00saliba.github.io/scapematch/parceiro/demo/#token',
        ),
        'https://nicolas00saliba.github.io/scapematch/parceiro/demo/',
      ),
      'https://nicolas00saliba.github.io/scapematch/parceiro/demo/',
    );
    expect(
      authReturnUrl(Uri.parse('https://app.escapematch.com.br/cadastro'), '/'),
      'https://app.escapematch.com.br/',
    );
    expect(
      authReturnUrl(Uri.parse('https://parceiro.escapematch.com.br/login'), '/'),
      'https://parceiro.escapematch.com.br/',
    );
    expect(
      authReturnUrl(
        Uri.parse('https://parceiro-demo.escapematch.com.br/agenda'),
        '/',
      ),
      'https://parceiro-demo.escapematch.com.br/',
    );
  });

  test('sem host ou sem base não há redirect', () {
    expect(
      authReturnUrl(Uri(path: '/scapematch/login'), '/scapematch/'),
      isNull,
    );
    expect(
      authReturnUrl(
        Uri.parse('https://nicolas00saliba.github.io/scapematch/'),
        '',
      ),
      isNull,
    );
  });

  test('a base ganha as barras do diretório', () {
    expect(directoryPath('scapematch'), '/scapematch/');
    expect(directoryPath('/scapematch/demo'), '/scapematch/demo/');
    expect(directoryPath('/scapematch/demo/?x=1#y'), '/scapematch/demo/');
    expect(directoryPath('/'), '/');
  });
}
