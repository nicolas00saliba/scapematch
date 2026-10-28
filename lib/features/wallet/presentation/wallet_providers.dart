import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/wallet/domain/money.dart';
import 'package:scapematch/providers/repositories.dart';

/// Saldo que a carteira da Conta mostra.
final walletBalanceProvider = FutureProvider<Money>((ref) {
  return ref.watch(walletRepositoryProvider).balance();
});

/// Cartões da conta. A lista de preparativos fica vazia nesta versão.
final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) {
  return ref.watch(paymentMethodsRepositoryProvider).list();
});
