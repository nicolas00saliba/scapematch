import 'package:scapematch/features/wallet/domain/money.dart';

/// Lado do lançamento no livro-razão. Crédito aumenta o saldo.
enum WalletTransactionKind { credit, debit }

/// Uma linha do saldo. O valor é sempre positivo; o [kind] diz o sinal.
///
/// Não carrega dado de cartão. A origem real (recarga, estorno, entrada
/// num grupo) entra depois no [description] e num id externo, não aqui.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.kind,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final Money amount;
  final WalletTransactionKind kind;
  final String description;
  final DateTime createdAt;

  /// Centavos com sinal. Débito fica negativo.
  int get signedCents {
    return kind == WalletTransactionKind.credit ? amount.cents : -amount.cents;
  }
}
