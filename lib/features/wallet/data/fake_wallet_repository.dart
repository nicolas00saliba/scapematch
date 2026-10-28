import 'package:scapematch/features/wallet/data/wallet_repository.dart';
import 'package:scapematch/features/wallet/domain/add_balance_outcome.dart';
import 'package:scapematch/features/wallet/domain/money.dart';
import 'package:scapematch/features/wallet/domain/wallet_transaction.dart';

/// Saldo de exemplo. R$ 40,00, um crédito só, e a recarga recusada.
///
/// O saldo é a soma dos lançamentos. [addBalance] não grava linha nova.
class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({
    List<WalletTransaction>? transactions,
    this.latency = Duration.zero,
  }) : _transactions = List<WalletTransaction>.unmodifiable(
         transactions ?? _sample,
       );

  static final _sample = <WalletTransaction>[
    WalletTransaction(
      id: 'txn-sample-opening',
      amount: const Money(4000),
      kind: WalletTransactionKind.credit,
      description: 'Saldo inicial de exemplo',
      createdAt: DateTime.utc(2026, 10, 27, 12),
    ),
  ];

  final List<WalletTransaction> _transactions;
  final Duration latency;

  @override
  Future<Money> balance() async {
    await _pause();
    final cents = _transactions.fold<int>(
      0,
      (sum, transaction) => sum + transaction.signedCents,
    );
    return Money(cents);
  }

  @override
  Future<List<WalletTransaction>> transactions() async {
    await _pause();
    return _transactions;
  }

  @override
  Future<AddBalanceOutcome> addBalance({
    required Money amount,
    required String idempotencyKey,
  }) async {
    await _pause();
    return const AddBalanceOutcome.unavailable();
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
