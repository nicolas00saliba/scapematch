import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final adminPeopleProvider = Provider<AdminPeopleApi>((ref) {
  if (!scapeUsesLiveBackend) return MemoryAdminPeopleApi();
  return SupabaseAdminPeopleApi(scapeSupabase);
});

abstract class AdminPeopleApi {
  Future<void> reopenVenue(String id);
  Future<void> setTest({required String kind, required String id, required bool enabled});
  Future<void> clearCommission(String venueId, String confirm);
  Future<void> mergeVenues(String sourceId, String targetId, String confirm);
  Future<int> adjustPoints({
    required String userId,
    required int points,
    required String direction,
    required String reason,
    required String confirm,
  });
  Future<PlayerLedger> ledger(String userId);
}

class PlayerLedger {
  const PlayerLedger({required this.isTest, required this.lines});
  final bool isTest;
  final List<String> lines;
}

class SupabaseAdminPeopleApi implements AdminPeopleApi {
  SupabaseAdminPeopleApi(this._client);
  final SupabaseClient _client;

  @override
  Future<void> reopenVenue(String id) async {
    await _client.rpc('admin_reopen_venue', params: {'p_venue_id': id});
  }

  @override
  Future<void> setTest({
    required String kind,
    required String id,
    required bool enabled,
  }) async {
    await _client.rpc('admin_set_account_test', params: {
      'p_kind': kind,
      'p_id': id,
      'p_enabled': enabled,
    });
  }

  @override
  Future<void> clearCommission(String venueId, String confirm) async {
    await _client.rpc('admin_clear_venue_commission', params: {
      'p_venue_id': venueId,
      'p_confirm': confirm,
    });
  }

  @override
  Future<void> mergeVenues(String sourceId, String targetId, String confirm) async {
    await _client.rpc('admin_merge_venues', params: {
      'p_source_id': sourceId,
      'p_target_id': targetId,
      'p_confirm': confirm,
    });
  }

  @override
  Future<int> adjustPoints({
    required String userId,
    required int points,
    required String direction,
    required String reason,
    required String confirm,
  }) async {
    final raw = await _client.rpc('admin_adjust_points', params: {
      'p_user_id': userId,
      'p_points': points,
      'p_direction': direction,
      'p_reason': reason,
      'p_confirm': confirm,
    });
    final row = raw is Map ? raw : const <String, dynamic>{};
    final value = row['available_points'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  @override
  Future<PlayerLedger> ledger(String userId) async {
    final raw = await _client.rpc('admin_player_ledger', params: {
      'p_user_id': userId,
    });
    final row = raw is Map ? raw : const <String, dynamic>{};
    final entries = row['entries'];
    return PlayerLedger(
      isTest: row['is_test'] == true,
      lines: [
        for (final item in entries is List ? entries : const [])
          if (item is Map) _line(item),
      ],
    );
  }

  String _line(Map item) {
    final place = '${item['room_name'] ?? ''} ${item['venue_name'] ?? ''}'.trim();
    final note = '${item['note'] ?? ''}'.trim();
    final where = place.isEmpty ? '' : ' · $place';
    final why = note.isEmpty ? '' : ' · $note';
    return '${item['kind']} ${item['points']} pts$where$why';
  }
}

class MemoryAdminPeopleApi implements AdminPeopleApi {
  MemoryAdminPeopleApi({this.venues});

  /// Quando presente, a casa de teste e a mescla valem também para a leitura
  /// da casa, como o servidor faz.
  final MemoryAdminApi? venues;
  bool reopened = false;
  bool playerTest = false;
  bool venueTest = false;
  bool cleared = false;
  bool merged = false;
  int available = 1800;
  final lines = <String>['admin_credit 12 pts · Sala do Caixa · Casa Destino · cortesia'];

  @override
  Future<void> reopenVenue(String id) async => reopened = true;

  @override
  Future<void> setTest({
    required String kind,
    required String id,
    required bool enabled,
  }) async {
    if (kind == 'player') {
      playerTest = enabled;
    } else {
      venueTest = enabled;
      venues?.markTest(id, enabled);
    }
  }

  @override
  Future<void> clearCommission(String venueId, String confirm) async {
    if (confirm != 'OFICIAL') throw const AdminRejected('confirmacao invalida');
    venues?.markOfficialCommission(venueId);
    cleared = true;
  }

  @override
  Future<void> mergeVenues(String sourceId, String targetId, String confirm) async {
    if (confirm != 'MESCLAR') throw const AdminRejected('confirmacao invalida');
    if (sourceId == targetId) throw const AdminRejected('casas invalidas');
    venues?.markMerged(sourceId, targetId);
    merged = true;
  }

  @override
  Future<int> adjustPoints({
    required String userId,
    required int points,
    required String direction,
    required String reason,
    required String confirm,
  }) async {
    if (confirm != 'PONTOS') throw const AdminRejected('confirmacao invalida');
    if (reason.trim().length < 3) throw const AdminRejected('ajuste invalido');
    available += direction == 'debit' ? -points : points;
    return available;
  }

  @override
  Future<PlayerLedger> ledger(String userId) async {
    return PlayerLedger(isTest: playerTest, lines: lines);
  }
}
