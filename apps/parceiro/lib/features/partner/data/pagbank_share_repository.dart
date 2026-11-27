import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Cidade da mesma casa com conta PagBank conectada, que pode emprestar a
/// conta para esta.
class PagbankShareSource {
  const PagbankShareSource({
    required this.venueId,
    required this.venueName,
    required this.accountLast4,
    this.cityName,
  });

  final String venueId;
  final String venueName;
  final String? cityName;
  final String accountLast4;

  String get label => cityName == null || cityName!.isEmpty
      ? venueName
      : '$cityName ($venueName)';

  static List<PagbankShareSource> listFrom(Object? data) {
    if (data is! List) return const [];
    return [
      for (final row in data)
        if (row is Map && row['venue_id'] is String)
          PagbankShareSource(
            venueId: row['venue_id'] as String,
            venueName: (row['venue_name'] as String?) ?? '',
            cityName: row['city_name'] as String?,
            accountLast4: (row['account_last4'] as String?) ?? '',
          ),
    ];
  }
}

typedef PagbankShareRpc = Future<Object?> Function(
  String fn,
  Map<String, Object?> params,
);

/// "Usar a mesma conta PagBank de outra cidade" (decisão do Nícolas, 27/11:
/// uma conta só pode receber por todas as cidades do mesmo dono).
class PagbankShareRepository {
  const PagbankShareRepository({this.rpc});

  final PagbankShareRpc? rpc;

  PagbankShareRpc get _call =>
      rpc ??
      (String fn, Map<String, Object?> params) =>
          scapeSupabase.rpc<Object?>(fn, params: params);

  /// Cidades da casa que podem emprestar a conta. Vazio em erro ou quando
  /// esta cidade já tem conta.
  Future<List<PagbankShareSource>> sources(String venueId) async {
    try {
      final data = await _call('my_pagbank_share_sources', {
        'p_venue_id': venueId,
      });
      return PagbankShareSource.listFrom(data);
    } on Object {
      return const [];
    }
  }

  /// Nulo quando ligou. A frase para a tela quando recusou.
  Future<String?> share(String venueId, String sourceVenueId) async {
    try {
      await _call('share_venue_pagbank_account', {
        'p_venue_id': venueId,
        'p_source_venue_id': sourceVenueId,
      });
      return null;
    } on PostgrestException catch (error) {
      return pagbankShareError(error.message);
    } on Object {
      return PagbankShareMessages.failed;
    }
  }
}

String pagbankShareError(String message) {
  if (message.contains('pagbank_account_exists')) {
    return PagbankShareMessages.exists;
  }
  if (message.contains('pagbank_share_invalid')) {
    return PagbankShareMessages.invalid;
  }
  if (message.contains('pagbank_account_in_use')) {
    return PagbankShareMessages.inUse;
  }
  if (message.contains('not owner')) return PagbankShareMessages.notOwner;
  return PagbankShareMessages.failed;
}

abstract final class PagbankShareMessages {
  static const title = 'Usar a conta de recebimento da casa';
  static String button(PagbankShareSource source) =>
      'Receber pela conta de ${source.label}'
      '${source.accountLast4.isEmpty ? '' : ' (final ${source.accountLast4})'}';
  static const body =
      'A casa tem uma conta de recebimento só, já conectada em outra cidade. Ligue esta cidade a ela para receber e sacar por essa conta. Salas e reservas continuam separadas por cidade.';
  static const confirmTitle = 'Receber pela conta da casa?';
  static const confirmBody =
      'Os pagamentos desta cidade vão cair na conta de recebimento da casa, e a nota fiscal sai pelo CNPJ dessa conta.';
  static const confirm = 'Usar esta conta';
  static const cancel = 'Cancelar';
  static const done = 'Esta cidade agora recebe pela conta da casa.';
  static const exists =
      'Esta cidade já tem conta PagBank. Para trocar, fale com o suporte.';
  static const invalid =
      'A outra cidade ainda não conectou a conta PagBank, ou não é da mesma casa.';
  static const inUse = 'Esta conta PagBank é de outra casa.';
  static const notOwner = 'Esta cidade não é da sua conta.';
  static const failed = 'Não foi possível ligar a conta. Tente de novo.';
}

final pagbankShareRepositoryProvider = Provider<PagbankShareRepository>(
  (ref) => const PagbankShareRepository(),
);
