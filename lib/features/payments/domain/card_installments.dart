/// Mínimo para parcelar. Abaixo disto só à vista.
const minCardInstallmentCents = 15000;

const maxCardInstallments = 12;

const interestFreeCardInstallments = 3;

/// Uma opção da grade. O total de 4x a 12x já inclui o juro cotado.
class CardInstallmentOption {
  const CardInstallmentOption({
    required this.count,
    required this.totalCents,
    required this.installmentCents,
    required this.interestFree,
    required this.enabled,
    this.disabledReason,
  });

  final int count;
  final int totalCents;
  final int installmentCents;
  final bool interestFree;
  final bool enabled;
  final String? disabledReason;

  bool get showsTotal => enabled && !interestFree && count > 1;
}

/// Texto curto da opção atual. À vista, ou "3x sem juros".
String installmentChoiceLabel(CardInstallmentOption option) {
  if (option.count <= 1) return 'À vista';
  final badge = option.interestFree ? 'sem juros' : 'com juros';
  return '${option.count}x $badge';
}

/// Parcela arredondada para cima, em centavos. O total cobrado é [totalCents].
int cardInstallmentCents(int totalCents, int count) {
  if (count <= 1) return totalCents;
  return (totalCents + count - 1) ~/ count;
}

/// 1x a 12x. Sem o juro cotado, 4x a 12x ficam desabilitadas.
///
/// [minAmountCents] só muda o piso desta lista. O app e o servidor
/// continuam em [minCardInstallmentCents].
List<CardInstallmentOption> cardInstallmentOptions({
  required int principalCents,
  Map<int, int> interestCentsByCount = const {},
  int minAmountCents = minCardInstallmentCents,
}) {
  final below = principalCents < minAmountCents;
  return [
    for (var count = 1; count <= maxCardInstallments; count++)
      _option(
        count: count,
        principalCents: principalCents,
        below: below,
        interest: interestCentsByCount[count],
      ),
  ];
}

CardInstallmentOption _option({
  required int count,
  required int principalCents,
  required bool below,
  required int? interest,
}) {
  final interestFree = count <= interestFreeCardInstallments;
  if (below && count > 1) {
    return CardInstallmentOption(
      count: count,
      totalCents: principalCents,
      installmentCents: cardInstallmentCents(principalCents, count),
      interestFree: interestFree,
      enabled: false,
      disabledReason: 'parcelamento a partir de R\$150',
    );
  }
  if (interestFree) {
    return CardInstallmentOption(
      count: count,
      totalCents: principalCents,
      installmentCents: cardInstallmentCents(principalCents, count),
      interestFree: true,
      enabled: true,
    );
  }
  if (interest == null || interest < 0) {
    return CardInstallmentOption(
      count: count,
      totalCents: principalCents,
      installmentCents: cardInstallmentCents(principalCents, count),
      interestFree: false,
      enabled: false,
      disabledReason: 'Cotação indisponível',
    );
  }
  final total = principalCents + interest;
  return CardInstallmentOption(
    count: count,
    totalCents: total,
    installmentCents: cardInstallmentCents(total, count),
    interestFree: false,
    enabled: true,
  );
}

/// Lê a resposta de `create-charge` com `action: quote_installments`.
List<CardInstallmentOption> cardInstallmentsFromQuote(
  Map<String, dynamic> body,
) {
  final plans = body['plans'];
  if (plans is! List) return const [];
  final options = <CardInstallmentOption>[];
  for (final item in plans) {
    if (item is! Map) continue;
    final count = item['installments'];
    final total = item['amount_cents'];
    if (count is! int || total is! int || count < 1 || count > 12) continue;
    final interestFree = item['interest_free'] == true;
    options.add(
      CardInstallmentOption(
        count: count,
        totalCents: total,
        installmentCents: cardInstallmentCents(total, count),
        interestFree: interestFree,
        enabled: item['enabled'] == true,
        disabledReason: item['enabled'] == true
            ? null
            : item['disabled_reason']?.toString() ?? 'Cotação indisponível',
      ),
    );
  }
  return options;
}
