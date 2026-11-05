import 'package:dominio/dominio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommissionRow {
  const CommissionRow({
    required this.venueId,
    required this.name,
    required this.commissionBps,
  });

  /// Nulo na linha da plataforma.
  final String? venueId;
  final String name;
  final int commissionBps;
}

abstract class CommissionAdminRepository {
  Future<List<CommissionRow>> board();

  /// Nulo quando gravou. Texto curto quando a taxa não entra.
  Future<String?> setPlatform(int commissionBps);

  Future<String?> setVenue(String venueId, int commissionBps);
}

class MemoryCommissionAdminRepository implements CommissionAdminRepository {
  MemoryCommissionAdminRepository({
    PlatformSettingsBook? book,
    this.houses = const {'house-1': 'Casa do Teste'},
    DateTime? at,
  }) : book = book ?? PlatformSettingsBook(),
       at = at ?? DateTime.utc(2026, 11, 5);

  final PlatformSettingsBook book;
  final Map<String, String> houses;
  final DateTime at;

  @override
  Future<List<CommissionRow>> board() async {
    final settings = book.settings;
    return [
      CommissionRow(
        venueId: null,
        name: 'ScapeMatch',
        commissionBps: settings.commissionBps,
      ),
      for (final house in houses.entries)
        CommissionRow(
          venueId: house.key,
          name: house.value,
          commissionBps: settings.rateFor(house.key),
        ),
    ];
  }

  @override
  Future<String?> setPlatform(int commissionBps) {
    return _write(
      () => book.setPlatformCommission(
        actorId: 'admin',
        role: PlatformRole.platformAdmin,
        commissionBps: commissionBps,
        at: at,
      ),
    );
  }

  @override
  Future<String?> setVenue(String venueId, int commissionBps) {
    return _write(
      () => book.setHouseCommission(
        actorId: 'admin',
        role: PlatformRole.platformAdmin,
        houseId: venueId,
        commissionBps: commissionBps,
        at: at,
      ),
    );
  }

  Future<String?> _write(void Function() apply) async {
    try {
      apply();
      return null;
    } on PaymentException catch (error) {
      return error.message;
    }
  }
}

class SupabaseCommissionAdminRepository implements CommissionAdminRepository {
  SupabaseCommissionAdminRepository(this.client);

  final SupabaseClient client;

  @override
  Future<List<CommissionRow>> board() async {
    final rows = await client.rpc('commission_board');
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          CommissionRow(
            venueId: row['venue_id']?.toString(),
            name: row['venue_name']?.toString() ?? 'Casa',
            commissionBps: row['commission_bps'] is int
                ? row['commission_bps'] as int
                : int.tryParse('${row['commission_bps']}') ?? 0,
          ),
    ];
  }

  @override
  Future<String?> setPlatform(int commissionBps) {
    return _rpc('set_platform_commission', {'p_commission_bps': commissionBps});
  }

  @override
  Future<String?> setVenue(String venueId, int commissionBps) {
    return _rpc('set_venue_commission', {
      'p_venue_id': venueId,
      'p_commission_bps': commissionBps,
    });
  }

  Future<String?> _rpc(String name, Map<String, dynamic> params) async {
    try {
      await client.rpc(name, params: params);
      return null;
    } on PostgrestException {
      return 'Não foi possível gravar a comissão.';
    }
  }
}

final commissionAdminRepositoryProvider = Provider<CommissionAdminRepository>((
  ref,
) {
  if (ref.watch(backendPlanProvider).connectsSupabase) {
    return SupabaseCommissionAdminRepository(scapeSupabase);
  }
  return MemoryCommissionAdminRepository();
});
