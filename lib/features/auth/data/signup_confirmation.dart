import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rede. A tela pode dizer que não saiu pedido nenhum.
const signupResendOfflineMessage = 'Sem conexão. Tente de novo.';

/// Limite do Auth, sem ecoar o corpo da API nem o e-mail.
const signupResendRateLimitMessage =
    'Muitas tentativas. Espere um pouco e tente de novo.';

/// O que a tela mostra quando o reenvio falha.
///
/// Nulo significa [signupResendNeutralMessage]: o Auth aceitou, a conta
/// não existe, ou a falha não é rede nem limite. A frase não muda, para
/// não contar se o endereço está cadastrado.
String? resendFailureMessage(Object error) {
  final raw = switch (error) {
    AuthException(:final message) => message,
    _ => error.toString(),
  };
  final text = raw.toLowerCase();
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('clientexception')) {
    return signupResendOfflineMessage;
  }
  if (text.contains('rate limit') ||
      text.contains('too many') ||
      text.contains('only request this')) {
    return signupResendRateLimitMessage;
  }
  return null;
}

/// Pede de novo o e-mail de confirmação do cadastro.
///
/// Nulo quando a tela deve usar [signupResendNeutralMessage], inclusive
/// se o Auth recusou por um motivo que revelaria a conta. Só volta frase
/// em falha de rede ou limite de taxa. O link abre em [emailRedirectTo],
/// o mesmo destino do cadastro.
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
    return resendFailureMessage(error);
  }
}
