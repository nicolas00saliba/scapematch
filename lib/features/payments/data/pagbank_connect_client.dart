import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/payments/data/pagbank_connect_return.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A casa já tem outra conta PagBank no servidor (409). A conta é da casa,
/// não do aparelho: só se troca desconectando a atual.
class PagbankConnectConflict implements Exception {
  const PagbankConnectConflict([this.message]);

  /// Texto do servidor (conta já tem outra, conta de outra casa...). Sem ele,
  /// vale a mensagem padrão.
  final String? message;
}

const pagbankConnectConflictMessage =
    'Esta casa já tem uma conta PagBank conectada. Para trocar, desconecte a atual na tela de saques e conecte de novo.';

/// Troca `code` e `state` na função `pagbank-connect`. O servidor decide;
/// nada fica no aparelho.
Future<bool> completePagbankConnectCall(PagbankConnectReturn hit) async {
  try {
    final response = await scapeSupabase.functions.invoke(
      'pagbank-connect',
      body: {'code': hit.code, 'state': hit.state},
    );
    final data = response.data;
    return data is Map && data['linked'] == true;
  } on FunctionException catch (error) {
    if (error.status == 409) {
      final details = error.details;
      final text = details is Map ? details['message'] : null;
      throw PagbankConnectConflict(
        text is String && text.trim().isNotEmpty ? text.trim() : null,
      );
    }
    rethrow;
  }
}
