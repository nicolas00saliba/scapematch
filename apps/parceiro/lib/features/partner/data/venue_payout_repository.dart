import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';

class VenuePayoutStatus {
  const VenuePayoutStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.receivesPayments,
  });

  final String id;
  final String name;
  final String status;
  final bool receivesPayments;

  VenuePayoutStatus copyWith({bool? receivesPayments}) {
    return VenuePayoutStatus(
      id: id,
      name: name,
      status: status,
      receivesPayments: receivesPayments ?? this.receivesPayments,
    );
  }
}

abstract class VenuePayoutRepository {
  Future<List<VenuePayoutStatus>> list();

  /// Nulo quando a função aceitou o pedido.
  Future<String?> retry(String venueId);
}

class MemoryVenuePayoutRepository implements VenuePayoutRepository {
  MemoryVenuePayoutRepository(this.rows);

  final List<VenuePayoutStatus> rows;
  final List<String> retried = [];

  @override
  Future<List<VenuePayoutStatus>> list() async => List.of(rows);

  @override
  Future<String?> retry(String venueId) async {
    retried.add(venueId);
    final index = rows.indexWhere((row) => row.id == venueId);
    if (index < 0) return 'Não foi possível criar a subconta.';
    rows[index] = rows[index].copyWith(receivesPayments: true);
    return null;
  }
}

class SupabaseVenuePayoutRepository implements VenuePayoutRepository {
  @override
  Future<List<VenuePayoutStatus>> list() async {
    final rows = await scapeSupabase
        .from('venues')
        .select('id, name, status, receives_payments')
        .order('name');
    return [
      for (final row in rows)
        VenuePayoutStatus(
          id: row['id'] as String,
          name: row['name']?.toString() ?? 'Casa',
          status: row['status']?.toString() ?? '',
          receivesPayments: row['receives_payments'] == true,
        ),
    ];
  }

  @override
  Future<String?> retry(String venueId) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'provision-venue-wallet',
        body: {'venue_id': venueId},
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        return 'Não foi possível criar a subconta.';
      }
      return null;
    } on Object {
      return 'Não foi possível criar a subconta.';
    }
  }
}

final venuePayoutRepositoryProvider = Provider<VenuePayoutRepository>((ref) {
  if (ref.watch(backendPlanProvider).connectsSupabase) {
    return SupabaseVenuePayoutRepository();
  }
  return MemoryVenuePayoutRepository(const []);
});
