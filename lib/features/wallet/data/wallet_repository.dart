import 'package:scapematch/features/wallet/domain/add_balance_outcome.dart';
import 'package:scapematch/features/wallet/domain/money.dart';
import 'package:scapematch/features/wallet/domain/wallet_transaction.dart';

/// Saldo e lançamentos da conta.
///
/// A tela da Conta lê [balance]. [addBalance] existe para o gateway entrar
/// no mesmo lugar. A tela de preparativos não chama [addBalance]: o botão
/// de confirmar fica desligado.
abstract class WalletRepository {
  Future<Money> balance();

  Future<List<WalletTransaction>> transactions();

  /// Não credita nesta versão. [idempotencyKey] fica reservada para o
  /// provedor não repetir a cobrança. Não mande número de cartão aqui.
  Future<AddBalanceOutcome> addBalance({
    required Money amount,
    required String idempotencyKey,
  });
}
