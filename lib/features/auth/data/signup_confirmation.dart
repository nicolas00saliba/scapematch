import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pede de novo o e-mail de confirmação do cadastro.
///
/// Nulo quando o Auth aceitou. Só funciona depois de um `signUp`
/// daquele endereço. O link abre em [emailRedirectTo], o mesmo
/// destino do cadastro.
Future<String?> resendSignupConfirmation({
  required SupabaseClient client,
  required String email,
  String? emailRedirectTo,
}) async {
  final trimmed = email.trim();
  if (!trimmed.contains('@')) return 'Informe um e-mail válido.';
  try {
    await client.auth.resend(
      type: OtpType.signup,
      email: trimmed,
      emailRedirectTo: emailRedirectTo,
    );
    return null;
  } on Object catch (error) {
    return authErrorMessage(
      error,
      fallback: 'Não foi possível reenviar o e-mail. Tente de novo.',
    );
  }
}
