import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Remove (desativa) uma unidade do login pelo RPC `deactivate_my_unit`.
///
/// Nada é apagado. O servidor confere o dono e recusa a última unidade
/// ativa, unidade com grupo futuro e unidade com saque pendente ou pagamento
/// ainda a liberar.
class PartnerUnitsRepository {
  const PartnerUnitsRepository({this.rpc});

  final Future<Object?> Function(String fn, Map<String, Object?> params)? rpc;

  /// Nulo quando removeu. A frase para a tela quando recusou.
  Future<String?> deactivate(String venueId) async {
    final call =
        rpc ??
        (String fn, Map<String, Object?> params) =>
            scapeSupabase.rpc<Object?>(fn, params: params);
    try {
      await call('deactivate_my_unit', {'p_venue_id': venueId});
      return null;
    } on PostgrestException catch (error) {
      return partnerUnitRemovalError(error.code, error.message);
    } on Object {
      return PartnerUnitMessages.failed;
    }
  }
}

/// Frase da recusa, pelo código e pela mensagem do Postgres.
String partnerUnitRemovalError(String? code, String message) {
  if (message.contains('unit_last')) return PartnerUnitMessages.last;
  if (message.contains('unit_future_groups')) {
    return PartnerUnitMessages.futureGroups;
  }
  if (message.contains('unit_pending_money')) {
    return PartnerUnitMessages.pendingMoney;
  }
  if (code == '42501') return PartnerUnitMessages.notOwner;
  if (code == 'PGRST202') return PartnerUnitMessages.unavailable;
  return PartnerUnitMessages.failed;
}

abstract final class PartnerUnitMessages {
  static const last =
      'Mantenha pelo menos uma unidade ativa. Cadastre outra antes de remover esta.';
  static const futureGroups =
      'Esta unidade tem grupos marcados. Cancele os grupos ou espere as sessões passarem antes de remover.';
  static const pendingMoney =
      'Esta unidade tem saque pendente ou pagamento ainda a liberar. Espere concluir antes de remover.';
  static const notOwner = 'Esta unidade não é da sua conta.';
  static const unavailable =
      'Remover unidade ainda não está disponível. Tente mais tarde.';
  static const failed = 'Não foi possível remover a unidade. Tente de novo.';
  static const removed = 'Unidade removida.';
}

final partnerUnitsRepositoryProvider = Provider<PartnerUnitsRepository>(
  (ref) => const PartnerUnitsRepository(),
);
