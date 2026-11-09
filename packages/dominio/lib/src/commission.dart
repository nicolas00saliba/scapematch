import 'package:dominio/src/payment_exception.dart';

/// 10000 basis points = 100%. 1000 = 10%.
const maxCommissionBps = 10000;

/// Comissão de [amountCents] à taxa [basisPoints], em centavos.
///
/// O meio centavo sobe. 7,5 centavos viram 8. A taxa entra como argumento:
/// esta conta não conhece os 10% iniciais da plataforma.
int commissionCents(int amountCents, int basisPoints) {
  _requireAmount(amountCents);
  _requireBps(basisPoints);
  return (amountCents * basisPoints + (maxCommissionBps ~/ 2)) ~/
      maxCommissionBps;
}

/// Reparte [totalCents] em [parts] inteiros que somam exatamente o total.
///
/// As primeiras partes levam o resto, um centavo cada.
List<int> splitCents(int totalCents, int parts) {
  _requireAmount(totalCents);
  if (parts <= 0) {
    throw PaymentException('A divisão precisa de pelo menos uma parte.');
  }
  final base = totalCents ~/ parts;
  final extra = totalCents % parts;
  return [for (var i = 0; i < parts; i++) base + (i < extra ? 1 : 0)];
}

/// Uma parte já com a comissão e o líquido que cabem nela.
class ShareQuote {
  const ShareQuote({
    required this.amountCents,
    required this.commissionCents,
    required this.netCents,
  });

  /// O que o jogador paga.
  final int amountCents;

  /// O que fica com o EscapeMatch.
  final int commissionCents;

  /// O que entra na conta da casa.
  final int netCents;
}

/// Divide o total e reparte a comissão do total entre as partes.
///
/// A comissão é calculada uma vez sobre o total e depois repartida, para
/// a soma das comissões bater com a taxa da reserva. Cada parte continua
/// com comissão + líquido = valor da parte.
List<ShareQuote> quoteShares({
  required int totalCents,
  required int playerCount,
  required int commissionBps,
}) {
  final amounts = splitCents(totalCents, playerCount);
  final totalCommission = commissionCents(totalCents, commissionBps);
  final commissions = _fitCommission(
    amounts,
    splitCents(totalCommission, playerCount),
  );
  return [
    for (var i = 0; i < amounts.length; i++)
      ShareQuote(
        amountCents: amounts[i],
        commissionCents: commissions[i],
        netCents: amounts[i] - commissions[i],
      ),
  ];
}

/// Garante que nenhuma parte fique com mais comissão do que o jogador paga,
/// sem mudar a soma da comissão.
List<int> _fitCommission(List<int> amounts, List<int> commissions) {
  final fitted = List<int>.of(commissions);
  var spare = 0;
  for (var i = 0; i < fitted.length; i++) {
    if (fitted[i] > amounts[i]) {
      spare += fitted[i] - amounts[i];
      fitted[i] = amounts[i];
    }
  }
  for (var i = 0; i < fitted.length && spare > 0; i++) {
    final room = amounts[i] - fitted[i];
    final give = room < spare ? room : spare;
    fitted[i] += give;
    spare -= give;
  }
  if (spare != 0) {
    throw PaymentException('A comissão não cabe nas partes da reserva.');
  }
  return fitted;
}

void _requireAmount(int amountCents) {
  if (amountCents < 0) {
    throw PaymentException('O valor não pode ser negativo.');
  }
}

void _requireBps(int basisPoints) {
  if (basisPoints < 0 || basisPoints > maxCommissionBps) {
    throw PaymentException(
      'A comissão fica entre 0 e $maxCommissionBps basis points.',
    );
  }
}
