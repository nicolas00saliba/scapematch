import 'package:scapematch_admin/admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Recusas do servidor que o Nícolas precisa entender sem abrir o banco.
/// A chave é um trecho da mensagem; a primeira que casar vence.
const _knownRejections = <String, String>{
  'confirmacao invalida': 'A palavra de confirmação não confere.',
  'casas invalidas': 'Escolha duas casas diferentes.',
  'casa de origem nao encontrada': 'A casa de origem não foi encontrada.',
  'casa de destino nao encontrada':
      'A casa que fica não foi encontrada. Confira o id.',
  'casa nao encontrada': 'A casa não foi encontrada.',
  'casa nao pode ser mesclada': 'Esta casa não pode ser mesclada: a origem já foi mesclada ou o destino está mesclado ou reprovado.',
  'casa com equipe': 'Não mescla: a casa de origem já tem equipe cadastrada.',
  'casa com acesso': 'Não mescla: a casa de origem já tem dono com acesso (PagBank, reivindicação ou dados fiscais).',
  'casa com saldo':
      'Não mescla: a casa de origem tem saldo ou lançamentos de crédito.',
  'casa com cobranca': 'Não mescla: a casa de origem já tem cobrança.',
  'casa com repasse': 'Não mescla: a casa de origem já tem repasse.',
  'mescla conflitante': 'Não mescla: as duas casas têm dados que colidem.',
  'so casa aprovada suspende': 'Só casa aprovada pode ser suspensa.',
  'e-mail oficial invalido': 'E-mail oficial inválido.',
  'telefone oficial invalido':
      'Telefone oficial inválido: de 10 a 13 números, com DDD.',
  'invalid input syntax for type uuid':
      'Id inválido. Cole o id completo da casa que fica.',
  'unknown venue': 'A casa não foi encontrada.',
};

/// Texto curto para o Nícolas quando uma leitura ou ação do painel falha.
/// Nada de stack trace nem de corpo cru da resposta.
String adminErrorText(Object error) {
  if (error is AdminRejected) return _known(error.message) ?? error.message;
  if (error is PostgrestException) {
    final message = error.message;
    if (message.contains('mfa obrigatorio')) {
      return 'A sessão perdeu o segundo fator. Saia e entre de novo.';
    }
    if (message.contains('not admin')) return 'Esta conta não é admin.';
    if (message.contains('not authenticated')) {
      return 'A sessão expirou. Entre de novo.';
    }
    final known = _known(message);
    if (known != null) return known;
    // O servidor já escreve em português claro as mensagens de campo
    // ("CEP: 8 números, sem hífen."); mostra como veio.
    if (error.code == '22023' && message.contains(':')) return message;
    return 'O servidor recusou: $message';
  }
  if (error is AuthException) return 'A sessão expirou. Entre de novo.';
  if (error is FunctionException) {
    return 'A função do servidor respondeu com erro (${error.status}).';
  }
  final kind = error.runtimeType.toString();
  if (kind.contains('ClientException') ||
      kind.contains('SocketException') ||
      kind.contains('TimeoutException')) {
    return 'Sem resposta do servidor. Confira a internet e tente de novo.';
  }
  return 'Não deu certo. Tente de novo.';
}

String? _known(String message) {
  final lower = message.toLowerCase();
  for (final entry in _knownRejections.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return null;
}
