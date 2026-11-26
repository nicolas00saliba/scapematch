import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Aviso depois do pedido. Não diz se o endereço tem conta.
const passwordResetSentMessage =
    'Se o e-mail tiver conta, o link já foi enviado.';

/// A demonstração não chama o Auth. A frase é a mesma do login de exemplo.
const passwordResetDemoMessage = 'Neste exemplo o link não é enviado.';

/// Erro do Auth que entregaria se o e-mail existe. Vira o aviso neutro.
bool passwordResetHidesAccount(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('user not found') ||
      text.contains('email not found') ||
      text.contains('no user');
}

/// Traduz o erro do Supabase Auth para a frase que a tela mostra.
String authErrorMessage(Object error, {required String fallback}) {
  final raw = switch (error) {
    AuthException(:final message) => message,
    _ => error.toString(),
  };
  final text = raw.toLowerCase();
  if (text.contains('invalid login') ||
      text.contains('invalid credentials') ||
      text.contains('invalid email or password')) {
    return 'E-mail ou senha não conferem.';
  }
  if (text.contains('already registered') ||
      text.contains('already been registered') ||
      text.contains('user already')) {
    return 'Esse e-mail já tem conta. Entre com ele.';
  }
  if (text.contains('pwned') ||
      text.contains('leaked') ||
      text.contains('known to be weak')) {
    return leakedPasswordMessage;
  }
  if (text.contains('password') &&
      (text.contains('short') ||
          text.contains('least') ||
          text.contains('weak') ||
          text.contains('character'))) {
    return passwordRuleMessage;
  }
  if (text.contains('invalid') && text.contains('email')) {
    return 'Esse e-mail não é válido.';
  }
  if (text.contains('rate limit') || text.contains('too many')) {
    return 'Muitas tentativas. Espere um pouco e tente de novo.';
  }
  if (text.contains('network') || text.contains('socket')) {
    return 'Sem conexão. Tente de novo.';
  }
  return fallback;
}
