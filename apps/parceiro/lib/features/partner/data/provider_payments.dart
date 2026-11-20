import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';

/// Pix na Woovi e cartão no Mercado Pago. Não há flag de provedor antigo.
final paymentsStackProvider = Provider<String>((ref) => 'woovi');

bool wooviPaymentsOn(String stack) => stack == 'woovi';

class WooviHouseBalance {
  const WooviHouseBalance({
    required this.balanceCents,
    required this.pixKeyMasked,
    required this.canWithdraw,
    required this.notice,
  });

  final int balanceCents;
  final String pixKeyMasked;
  final bool canWithdraw;
  final String notice;
}

abstract class ProviderPaymentsRepository {
  Future<WooviHouseBalance> balance(String venueId);

  Future<void> withdraw({required String venueId, required int amountCents});

  Future<Uri> mpConnectUrl(String venueId);
}

class SupabaseProviderPaymentsRepository implements ProviderPaymentsRepository {
  const SupabaseProviderPaymentsRepository();

  @override
  Future<WooviHouseBalance> balance(String venueId) async {
    final data = await _invoke('venue-payouts', {
      'action': 'woovi_balance',
      'venue_id': venueId,
    });
    return WooviHouseBalance(
      balanceCents: data['balance_cents'] as int? ?? 0,
      pixKeyMasked: data['pix_key_masked'] as String? ?? '',
      canWithdraw: data['can_withdraw'] == true,
      notice: data['notice'] as String? ?? '',
    );
  }

  @override
  Future<void> withdraw({
    required String venueId,
    required int amountCents,
  }) async {
    await _invoke('venue-payouts', {
      'action': 'woovi_withdraw',
      'venue_id': venueId,
      'amount_cents': amountCents,
    });
  }

  @override
  Future<Uri> mpConnectUrl(String venueId) async {
    final data = await _invoke('mp-oauth', {
      'action': 'start',
      'venue_id': venueId,
    });
    final url = data['url'] as String? ?? '';
    return Uri.parse(url);
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body,
  ) async {
    final response = await scapeSupabase.functions.invoke(name, body: body);
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw ProviderPaymentsFailure(data['error'].toString());
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ProviderPaymentsFailure('erro');
  }
}

class ProviderPaymentsFailure implements Exception {
  const ProviderPaymentsFailure(this.code);

  final String code;
}

final providerPaymentsRepositoryProvider = Provider<ProviderPaymentsRepository>(
  (ref) => const SupabaseProviderPaymentsRepository(),
);
