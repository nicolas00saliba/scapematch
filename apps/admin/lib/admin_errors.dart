import 'package:scapematch_admin/admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Texto curto para o Nícolas quando uma leitura ou ação do painel falha.
/// Nada de stack trace nem de corpo cru da resposta.
String adminErrorText(Object error) {
  if (error is AdminRejected) return error.message;
  if (error is PostgrestException) {
    final message = error.message;
    if (message.contains('mfa obrigatorio')) {
      return 'A sessão perdeu o segundo fator. Saia e entre de novo.';
    }
    if (message.contains('not admin')) return 'Esta conta não é admin.';
    if (message.contains('not authenticated')) {
      return 'A sessão expirou. Entre de novo.';
    }
    return 'O servidor recusou: $message';
  }
  if (error is FunctionException) {
    return 'A função do servidor respondeu com erro (${error.status}).';
  }
  return 'Não deu certo. Tente de novo.';
}
