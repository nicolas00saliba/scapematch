import 'package:scapematch/features/payments/data/payment_methods_repository.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cartões do jogador logado. A função `my_saved_cards` não devolve o token.
class SupabasePaymentMethodsRepository implements PaymentMethodsRepository {
  SupabasePaymentMethodsRepository(this.client);

  final SupabaseClient client;

  @override
  Future<List<PaymentMethod>> list() async {
    final rows = await client.rpc('my_saved_cards');
    if (rows is! List) {
      return const [];
    }
    final methods = <PaymentMethod>[];
    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final id = row['id']?.toString() ?? '';
      final last4 = row['last4']?.toString() ?? '';
      if (id.isEmpty || !RegExp(r'^\d{4}$').hasMatch(last4)) {
        continue;
      }
      methods.add(
        PaymentMethod(
          id: id,
          brand: cardBrandFromAsaas(row['brand']?.toString() ?? ''),
          last4: last4,
          nickname: 'Cartão',
        ),
      );
    }
    return methods;
  }
}

CardBrand cardBrandFromAsaas(String value) {
  final text = value.toLowerCase();
  if (text.contains('visa')) {
    return CardBrand.visa;
  }
  if (text.contains('master')) {
    return CardBrand.mastercard;
  }
  if (text.contains('elo')) {
    return CardBrand.elo;
  }
  return CardBrand.other;
}
