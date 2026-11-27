import 'package:flutter/foundation.dart';
import 'package:scapematch/core/sharing/public_origins.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/auth_redirect.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raiz do Parceiro para o e-mail de senha.
///
/// Com `<base href>` usa a mesma conta do jogador (`authReturnUrl`):
/// em produção isso é `https://parceiro.escapematch.com.br/`. Sem base,
/// cai nessa origem pública para o link não voltar ao app do jogador.
String partnerPasswordResetRedirect({Uri? page, String? baseHref}) {
  return webAuthRedirect(page, baseHref) ?? '$partnerAppOrigin/';
}

/// Pede o e-mail. Nulo quando o pedido foi aceito ou quando a demonstração
/// não chama o Auth. A frase não revela se o endereço existe.
Future<String?> requestPartnerPasswordReset(String email) async {
  final trimmed = email.trim();
  if (!trimmed.contains('@')) return 'Informe um e-mail válido.';
  if (!scapeUsesLiveBackend) return null;
  try {
    await scapeSupabase.auth.resetPasswordForEmail(
      trimmed,
      redirectTo: kIsWeb ? partnerPasswordResetRedirect() : null,
    );
    return null;
  } on Object catch (error) {
    if (passwordResetHidesAccount(error)) return null;
    return authErrorMessage(
      error,
      fallback: 'Não foi possível enviar o e-mail. Tente de novo.',
    );
  }
}

/// Grava a senha da sessão de recuperação com `auth.updateUser`.
/// A demonstração não chama o Auth.
Future<String?> updatePartnerPassword(String password) async {
  if (!scapeUsesLiveBackend) return passwordResetDemoMessage;
  final rejected = await rejectPassword(password);
  if (rejected != null) return rejected;
  try {
    await scapeSupabase.auth.updateUser(UserAttributes(password: password));
    return null;
  } on Object catch (error) {
    return authErrorMessage(
      error,
      fallback: 'Não foi possível trocar a senha. Tente de novo.',
    );
  }
}
