import 'package:scapematch/features/payments/domain/player_charge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pagamentos da conta logada. A função `my_payments` respeita o RLS.
abstract class PlayerPaymentsRepository {
  Future<List<PlayerCharge>> list();
}

class EmptyPlayerPaymentsRepository implements PlayerPaymentsRepository {
  const EmptyPlayerPaymentsRepository();

  @override
  Future<List<PlayerCharge>> list() async => const [];
}

class MemoryPlayerPaymentsRepository implements PlayerPaymentsRepository {
  MemoryPlayerPaymentsRepository(this.charges);

  final List<PlayerCharge> charges;

  @override
  Future<List<PlayerCharge>> list() async => List.of(charges);
}

class SupabasePlayerPaymentsRepository implements PlayerPaymentsRepository {
  SupabasePlayerPaymentsRepository(this.client);

  final SupabaseClient client;

  @override
  Future<List<PlayerCharge>> list() async {
    final rows = await client.rpc('my_payments');
    if (rows is! List) return const [];
    final charges = <PlayerCharge>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['id']?.toString() ?? '';
      final chargedAt = DateTime.tryParse(row['charged_at']?.toString() ?? '');
      if (id.isEmpty || chargedAt == null) continue;
      charges.add(
        PlayerCharge(
          id: id,
          amountCents: _cents(row['amount_cents']),
          roomName: row['room_name']?.toString() ?? 'Sala',
          chargedAt: chargedAt.toLocal(),
          status: row['status']?.toString() ?? '',
          refunded: row['refunded'] == true,
        ),
      );
    }
    return charges;
  }
}

int _cents(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
