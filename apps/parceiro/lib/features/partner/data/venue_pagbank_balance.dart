import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';

enum VenuePagbankBalanceKind { live, unavailable, absent }

/// Saldo lido na PagBank. Centavos ausentes não viram zero.
class VenuePagbankBalance {
  const VenuePagbankBalance._({
    required this.kind,
    this.availableCents,
    this.blockedCents,
    this.heldCents,
  });

  const VenuePagbankBalance.absent()
    : this._(kind: VenuePagbankBalanceKind.absent);

  const VenuePagbankBalance.unavailable()
    : this._(kind: VenuePagbankBalanceKind.unavailable);

  const VenuePagbankBalance.live({
    required int availableCents,
    int? blockedCents,
    int? heldCents,
  }) : this._(
         kind: VenuePagbankBalanceKind.live,
         availableCents: availableCents,
         blockedCents: blockedCents,
         heldCents: heldCents,
       );

  final VenuePagbankBalanceKind kind;
  final int? availableCents;
  final int? blockedCents;
  final int? heldCents;
}

abstract class VenuePagbankBalanceRepository {
  Future<VenuePagbankBalance> load(String venueId);
}

class MemoryVenuePagbankBalanceRepository
    implements VenuePagbankBalanceRepository {
  const MemoryVenuePagbankBalanceRepository(this.value);

  final VenuePagbankBalance value;

  @override
  Future<VenuePagbankBalance> load(String venueId) async => value;
}

class SupabaseVenuePagbankBalanceRepository
    implements VenuePagbankBalanceRepository {
  @override
  Future<VenuePagbankBalance> load(String venueId) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'venue-pagbank-balance',
        body: {'venue_id': venueId},
      );
      final data = response.data;
      if (data is! Map) return const VenuePagbankBalance.unavailable();
      final status = data['status'];
      if (status == 'unlinked') return const VenuePagbankBalance.absent();
      if (status != 'ok') return const VenuePagbankBalance.unavailable();
      final available = _cents(data['available_cents']);
      if (available == null) return const VenuePagbankBalance.unavailable();
      return VenuePagbankBalance.live(
        availableCents: available,
        blockedCents: _cents(data['blocked_cents']),
        heldCents: _cents(data['held_cents']),
      );
    } on Object {
      return const VenuePagbankBalance.unavailable();
    }
  }
}

int? _cents(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.round();
  }
  return null;
}

final venuePagbankBalanceRepositoryProvider =
    Provider<VenuePagbankBalanceRepository>((ref) {
      if (!ref.watch(backendPlanProvider).connectsSupabase) {
        return const MemoryVenuePagbankBalanceRepository(
          VenuePagbankBalance.absent(),
        );
      }
      return SupabaseVenuePagbankBalanceRepository();
    });

final venuePagbankBalanceProvider =
    FutureProvider.family<VenuePagbankBalance, String>((ref, venueId) {
      return ref.watch(venuePagbankBalanceRepositoryProvider).load(venueId);
    });
