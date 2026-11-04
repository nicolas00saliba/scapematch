import 'package:supabase_flutter/supabase_flutter.dart';

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
  if (text.contains('password') &&
      (text.contains('short') ||
          text.contains('least') ||
          text.contains('weak') ||
          text.contains('6'))) {
    return 'A senha precisa de pelo menos 6 caracteres.';
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
