import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ClientException implements Exception {}

void main() {
  test('recusas de mescla viram frase que o Nícolas entende', () {
    expect(
      adminErrorText(const PostgrestException(message: 'casa com acesso')),
      contains('dono com acesso'),
    );
    expect(
      adminErrorText(const PostgrestException(message: 'casa com equipe')),
      contains('equipe'),
    );
    expect(
      adminErrorText(
        const PostgrestException(
          message: 'invalid input syntax for type uuid: "abc"',
        ),
      ),
      'Id inválido. Cole o id completo da casa que fica.',
    );
    expect(
      adminErrorText(const PostgrestException(message: 'confirmacao invalida')),
      'A palavra de confirmação não confere.',
    );
    expect(
      adminErrorText(const AdminRejected('so casa aprovada suspende')),
      'Só casa aprovada pode ser suspensa.',
    );
  });

  test('mensagem de campo do servidor passa como veio', () {
    expect(
      adminErrorText(
        const PostgrestException(
          message: 'CEP: 8 números, sem hífen.',
          code: '22023',
        ),
      ),
      'CEP: 8 números, sem hífen.',
    );
  });

  test('sessão, rede e função têm texto próprio', () {
    expect(
      adminErrorText(const AuthException('JWT expired')),
      'A sessão expirou. Entre de novo.',
    );
    expect(
      adminErrorText(_ClientException()),
      'Sem resposta do servidor. Confira a internet e tente de novo.',
    );
    expect(
      adminErrorText(const PostgrestException(message: 'algo novo')),
      'O servidor recusou: algo novo',
    );
  });
}
