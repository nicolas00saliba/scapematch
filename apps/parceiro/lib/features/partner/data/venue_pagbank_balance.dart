import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';

enum VenuePagbankBalanceKind { live, unavailable, unlinked, absent }

/// Saldo lido na PagBank. Centavos ausentes não viram zero.
class VenuePagbankBalance {
  const VenuePagbankBalance._({
    required this.kind,
    this.availableCents,
    this.blockedCents,
    this.heldCents,
    this.readAt,
    this.forbidden = false,
  });

  const VenuePagbankBalance.absent()
    : this._(kind: VenuePagbankBalanceKind.absent);

  /// [forbidden]: a PagBank negou a consulta (permissão). Sem isso, foi falha.
  const VenuePagbankBalance.unavailable({bool forbidden = false})
    : this._(kind: VenuePagbankBalanceKind.unavailable, forbidden: forbidden);

  /// A casa tem conta PagBank, mas o app não tem a conexão para ler o saldo.
  const VenuePagbankBalance.unlinked()
    : this._(kind: VenuePagbankBalanceKind.unlinked);

  const VenuePagbankBalance.live({
    required int availableCents,
    int? blockedCents,
    int? heldCents,
    DateTime? readAt,
  }) : this._(
         kind: VenuePagbankBalanceKind.live,
         availableCents: availableCents,
         blockedCents: blockedCents,
         heldCents: heldCents,
         readAt: readAt,
       );

  final VenuePagbankBalanceKind kind;
  final int? availableCents;
  final int? blockedCents;
  final int? heldCents;

  /// Horário em que a PagBank respondeu, nunca o de um cálculo interno.
  final DateTime? readAt;
  final bool forbidden;
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
      if (status == 'unlinked') return const VenuePagbankBalance.unlinked();
      if (status != 'ok') {
        return VenuePagbankBalance.unavailable(
          forbidden: data['reason'] == 'forbidden',
        );
      }
      final available = _cents(data['available_cents']);
      if (available == null) return const VenuePagbankBalance.unavailable();
      final readAt = data['read_at'];
      return VenuePagbankBalance.live(
        availableCents: available,
        blockedCents: _cents(data['blocked_cents']),
        heldCents: _cents(data['held_cents']),
        readAt:
            (readAt is String ? DateTime.tryParse(readAt)?.toLocal() : null) ??
            DateTime.now(),
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

/// Sem cache entre telas: abrir o saldo lê a PagBank de novo.
final venuePagbankBalanceProvider = FutureProvider.autoDispose
    .family<VenuePagbankBalance, String>((ref, venueId) {
      return ref.watch(venuePagbankBalanceRepositoryProvider).load(venueId);
    });
