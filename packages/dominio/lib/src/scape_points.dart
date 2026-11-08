import 'package:dominio/src/commission.dart';

/// Regras do Modelo 2. Os números abaixo são o padrão aprovado;
/// o banco guarda a mesma tabela e pode mudá-la sem recompilar o app.
///
/// 1 Scape Point vale [ReferralRates.pointValueCents] centavos.
/// O padrão é 1 ponto = R\$ 0,01. O ponto não vence e não saca:
/// só abate sala. A casa continua recebendo o líquido cheio;
/// o abatimento sai da comissão da ScapeMatch.
class ReferralRates {
  const ReferralRates({
    this.c2cBps = 250,
    this.b2cBps = 250,
    this.c2bBps = 250,
    this.b2bBps = 500,
    this.pointValueCents = 1,
    this.attributionDays = 365,
    this.holdDays = 30,
    this.cashbackBps = 100,
    this.firstBookingDiscountBps = 2000,
  });

  /// Jogador que indicou outro jogador, sobre o gasto do indicado.
  final int c2cBps;

  /// Casa que indicou o jogador, sobre o gasto dele em outra casa.
  final int b2cBps;

  /// Jogador que indicou a casa, sobre o faturamento dela na plataforma.
  final int c2bBps;

  /// Casa que indicou outra casa. Não incide na reserva com desconto de primeira visita.
  final int b2bBps;

  /// Centavos de um ponto. 1 = R\$ 0,01.
  final int pointValueCents;

  /// Janela da indicação, em dias, contada do cadastro de quem foi indicado.
  final int attributionDays;

  /// Dias em que o crédito fica pendente antes de poder pagar sala.
  final int holdDays;

  /// Cashback do jogador que pagou, sobre a parte que ele pagou.
  /// 100 = 1%. Sai da comissão que sobrou.
  final int cashbackBps;

  /// Desconto da primeira reserva com código, em basis points.
  /// Não é aplicado sozinho. Quando a cobrança traz esse desconto,
  /// o B2B daquela reserva não é lançado.
  final int firstBookingDiscountBps;

  static const official = ReferralRates();
}

/// Quem ganha o lançamento: pontos do jogador ou crédito pendente da casa.
enum RewardPayee { playerPoints, venueCredit }

class RewardLine {
  const RewardLine({
    required this.program,
    required this.cents,
    required this.points,
    required this.payee,
  });

  /// `cashback`, `c2c`, `b2c`, `c2b` ou `b2b`.
  final String program;
  final int cents;
  final int points;
  final RewardPayee payee;

  bool get posts => payee == RewardPayee.venueCredit ? cents > 0 : points > 0;
}

class AttributionSlice {
  const AttributionSlice({
    required this.startsAt,
    required this.endsAt,
    this.blocked = false,
  });

  final DateTime startsAt;
  final DateTime endsAt;
  final bool blocked;
}

class SpendRewardInput {
  const SpendRewardInput({
    required this.grossCents,
    required this.commissionBps,
    required this.paidAt,
    this.subsidyCents = 0,
    this.firstBookingDiscountCents = 0,
    this.playerReferrer,
    this.playerReferrerIsVenue = false,
    this.spendAtReferrerVenue = false,
    this.venueReferrer,
    this.venueReferrerIsPlayer = false,
    this.payerCpfMissing = false,
    this.playerReferrerCpfMissing = false,
    this.venueReferrerCpfMissing = false,
    this.fraudReason,
  });

  final int grossCents;
  final int commissionBps;
  final int subsidyCents;

  /// Desconto de primeira reserva já fotografado nesta cobrança.
  /// Maior que zero: esta reserva não gera B2B.
  final int firstBookingDiscountCents;
  final DateTime paidAt;

  /// Janela de quem indicou o jogador que pagou. Nula se ninguém indicou.
  final AttributionSlice? playerReferrer;

  /// Verdadeiro quando quem indicou o jogador é uma casa (B2C).
  final bool playerReferrerIsVenue;

  /// O gasto foi na própria casa que indicou o jogador.
  final bool spendAtReferrerVenue;

  /// Janela de quem indicou a casa desta reserva.
  final AttributionSlice? venueReferrer;

  /// Verdadeiro quando quem indicou a casa é um jogador (C2B).
  final bool venueReferrerIsPlayer;

  final bool payerCpfMissing;
  final bool playerReferrerCpfMissing;
  final bool venueReferrerCpfMissing;

  /// Fraude já decidida. Não lança e a atribuição deve ser bloqueada.
  final String? fraudReason;
}

class PointSubsidyQuote {
  const PointSubsidyQuote({
    required this.grossCents,
    required this.chargedCents,
    required this.subsidyCents,
    required this.points,
    required this.houseNetCents,
    required this.commissionCents,
    required this.splitPercent,
    required this.maxPoints,
  });

  final int grossCents;
  final int chargedCents;
  final int subsidyCents;
  final int points;
  final int houseNetCents;
  final int commissionCents;

  /// Nulo quando não há abatimento: o split percentual antigo continua.
  /// Com abatimento, é o percentual (até 4 casas) que devolve o líquido
  /// cheio da casa sobre o valor menor cobrado do jogador.
  final double? splitPercent;
  final int maxPoints;
}

/// Fim da janela. O instante final não entra (`paidAt < fim`).
DateTime attributionEndsAt(DateTime startedAt, int days) {
  if (days <= 0) {
    throw ArgumentError('A janela da indicação precisa de ao menos um dia.');
  }
  return startedAt.add(Duration(days: days));
}

bool attributionCovers(AttributionSlice slice, DateTime paidAt) {
  if (slice.blocked) return false;
  return !paidAt.isBefore(slice.startsAt) && paidAt.isBefore(slice.endsAt);
}

DateTime pointsAvailableAt(DateTime paidAt, int holdDays) {
  if (holdDays < 0) {
    throw ArgumentError('A carência não pode ser negativa.');
  }
  return paidAt.add(Duration(days: holdDays));
}

/// `matched` quando o documento de quem pagou é o CPF da conta.
/// Máscara, ausência ou tamanho diferente de 11/14 fica `unverified`.
String payerDocumentStatus({
  required String? accountCpf,
  required String? payerDocument,
}) {
  final account = _fullDocument(accountCpf);
  final payer = _fullDocument(payerDocument);
  if (account == null || payer == null) return 'unverified';
  return account == payer ? 'matched' : 'mismatch';
}

/// Recompensa e desconto de indicação só com CPF conferido.
bool referralBenefitAllowed(String? payerStatus) => payerStatus == 'matched';

/// O desconto da primeira reserva usa a mesma trava do CPF do pagador.
int gatedFirstBookingDiscountCents({
  required String? payerStatus,
  required int grossCents,
  required int discountBps,
  required int commissionCentsValue,
}) {
  if (!referralBenefitAllowed(payerStatus)) return 0;
  return firstBookingDiscountCents(
    grossCents: grossCents,
    discountBps: discountBps,
    commissionCentsValue: commissionCentsValue,
  );
}

int pointsFromCents(int cents, int pointValueCents) {
  _requirePointValue(pointValueCents);
  if (cents <= 0) return 0;
  return cents ~/ pointValueCents;
}

int centsFromPoints(int points, int pointValueCents) {
  _requirePointValue(pointValueCents);
  if (points <= 0) return 0;
  return points * pointValueCents;
}

/// Desconto da primeira reserva, limitado à comissão. Não entra no
/// lançamento automático; existe para o ledger tratar o mesmo teto
/// quando o desconto for ligado.
int firstBookingDiscountCents({
  required int grossCents,
  required int discountBps,
  required int commissionCentsValue,
}) {
  if (commissionCentsValue < 0) {
    throw ArgumentError('A comissão não pode ser negativa.');
  }
  final wanted = commissionCents(grossCents, discountBps);
  return wanted > commissionCentsValue ? commissionCentsValue : wanted;
}

/// CPF, telefone e cartão iguais, ou CPF do jogador igual ao da casa.
/// Não devolve o documento. `shared_card` só quando o token é o mesmo.
String? referralFraudReason({
  String? leftCpf,
  String? rightCpf,
  String? leftPhone,
  String? rightPhone,
  bool sharedCardToken = false,
  String? playerCpf,
  String? venueDocument,
  String? venueOwnerCpf,
}) {
  if (sharedCardToken) return 'shared_card';
  final left = _digits(leftCpf);
  final right = _digits(rightCpf);
  if (left != null && right != null && left == right) return 'shared_cpf';
  final phoneLeft = _digits(leftPhone);
  final phoneRight = _digits(rightPhone);
  if (phoneLeft != null &&
      phoneRight != null &&
      phoneLeft.isNotEmpty &&
      phoneLeft == phoneRight) {
    return 'shared_phone';
  }
  final player = _digits(playerCpf);
  final venue = _digits(venueDocument);
  final owner = _digits(venueOwnerCpf);
  if (player != null && venue != null && player == venue) {
    return 'player_owns_venue';
  }
  if (player != null && owner != null && player == owner) {
    return 'player_owns_venue';
  }
  return null;
}

/// Recompensas de um nível. O cashback do pagador sai primeiro, da comissão
/// que sobrou depois dos pontos e do desconto de primeira reserva. Depois
/// vem a indicação do jogador e a da casa. O B2B não entra na reserva que
/// levou esse desconto. O líquido da casa não entra nessa conta.
List<RewardLine> quoteReferralRewards(
  SpendRewardInput input, {
  ReferralRates rates = ReferralRates.official,
}) {
  _requirePointValue(rates.pointValueCents);
  final gross = input.grossCents;
  final commission = commissionCents(gross, input.commissionBps);
  var pool = commission - input.subsidyCents - input.firstBookingDiscountCents;
  if (pool < 0) pool = 0;
  final lines = <RewardLine>[];

  final paid = gross - input.subsidyCents;
  final cash = _takePoints(
    paid,
    rates.cashbackBps,
    pool,
    rates.pointValueCents,
  );
  if (cash.points > 0) {
    lines.add(
      RewardLine(
        program: 'cashback',
        cents: cash.cents,
        points: cash.points,
        payee: RewardPayee.playerPoints,
      ),
    );
    pool -= cash.cents;
  }

  final player = input.fraudReason == null ? input.playerReferrer : null;
  if (player != null &&
      attributionCovers(player, input.paidAt) &&
      !input.payerCpfMissing) {
    if (input.playerReferrerIsVenue) {
      if (!input.spendAtReferrerVenue) {
        final cents = _takeCents(gross, rates.b2cBps, pool);
        if (cents > 0) {
          lines.add(
            RewardLine(
              program: 'b2c',
              cents: cents,
              points: 0,
              payee: RewardPayee.venueCredit,
            ),
          );
          pool -= cents;
        }
      }
    } else if (!input.playerReferrerCpfMissing) {
      final taken = _takePoints(
        gross,
        rates.c2cBps,
        pool,
        rates.pointValueCents,
      );
      if (taken.points > 0) {
        lines.add(
          RewardLine(
            program: 'c2c',
            cents: taken.cents,
            points: taken.points,
            payee: RewardPayee.playerPoints,
          ),
        );
        pool -= taken.cents;
      }
    }
  }

  final venue = input.fraudReason == null ? input.venueReferrer : null;
  if (venue != null && attributionCovers(venue, input.paidAt)) {
    if (input.venueReferrerIsPlayer) {
      if (!input.venueReferrerCpfMissing) {
        final taken = _takePoints(
          gross,
          rates.c2bBps,
          pool,
          rates.pointValueCents,
        );
        if (taken.points > 0) {
          lines.add(
            RewardLine(
              program: 'c2b',
              cents: taken.cents,
              points: taken.points,
              payee: RewardPayee.playerPoints,
            ),
          );
        }
      }
    } else if (input.firstBookingDiscountCents <= 0) {
      final cents = _takeCents(gross, rates.b2bBps, pool);
      if (cents > 0) {
        lines.add(
          RewardLine(
            program: 'b2b',
            cents: cents,
            points: 0,
            payee: RewardPayee.venueCredit,
          ),
        );
      }
    }
  }

  return lines;
}

/// Abate pontos do valor cobrado do jogador. O líquido da casa fica o do
/// preço cheio. O percentual novo só existe quando há abatimento; ele é
/// arredondado para cima em 4 casas, que é o limite do Asaas.
PointSubsidyQuote quotePointSubsidy({
  required int grossCents,
  required int commissionBps,
  required int requestedPoints,
  required int availablePoints,
  ReferralRates rates = ReferralRates.official,
}) {
  _requirePointValue(rates.pointValueCents);
  if (grossCents <= 0) {
    throw ArgumentError('A reserva precisa de um valor.');
  }
  final commission = commissionCents(grossCents, commissionBps);
  final houseNet = grossCents - commission;
  final room = grossCents > 1 ? grossCents - 1 : 0;
  final maxSubsidy = commission < room ? commission : room;
  final maxPoints = pointsFromCents(
    maxSubsidy < 0 ? 0 : maxSubsidy,
    rates.pointValueCents,
  );
  var points = requestedPoints;
  if (points < 0) points = 0;
  if (points > availablePoints) points = availablePoints;
  if (points > maxPoints) points = maxPoints;
  final subsidy = centsFromPoints(points, rates.pointValueCents);
  final charged = grossCents - subsidy;
  final split = subsidy == 0
      ? null
      : subsidizedHouseSplitPercent(
          houseNetCents: houseNet,
          chargedCents: charged,
        );
  return PointSubsidyQuote(
    grossCents: grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points: points,
    houseNetCents: houseNet,
    commissionCents: commission,
    splitPercent: split,
    maxPoints: maxPoints,
  );
}

/// Percentual do valor cobrado (já com abatimento) que devolve o líquido
/// cheio da casa. Sobe na 4ª casa decimal para a casa não perder centavo
/// por arredondamento. O Asaas aplica esse percentual sobre o líquido
/// depois da taxa dele; o centavo que sobrar sai da ScapeMatch.
double subsidizedHouseSplitPercent({
  required int houseNetCents,
  required int chargedCents,
}) {
  if (chargedCents <= 0) {
    throw ArgumentError('A cobrança ficou sem valor.');
  }
  if (houseNetCents < 0 || houseNetCents > chargedCents) {
    throw ArgumentError('O líquido da casa não cabe na cobrança.');
  }
  if (houseNetCents == 0) return 0;
  final scaled = (houseNetCents * 1000000 + chargedCents - 1) ~/ chargedCents;
  final percent = scaled / 10000;
  if (percent > 100) {
    throw ArgumentError('O split passou de 100%.');
  }
  return percent;
}

String accrualIdempotencyKey(String chargeId, String program) {
  return 'accrual:$chargeId:$program';
}

/// Segunda chamada com a mesma chave não gera outra linha.
List<RewardLine> postRewardsOnce({
  required Set<String> existingKeys,
  required String chargeId,
  required List<RewardLine> lines,
}) {
  final posted = <RewardLine>[];
  for (final line in lines) {
    if (!line.posts) continue;
    final key = accrualIdempotencyKey(chargeId, line.program);
    if (existingKeys.add(key)) posted.add(line);
  }
  return posted;
}

int _takeCents(int grossCents, int bps, int pool) {
  if (pool <= 0 || bps <= 0) return 0;
  final raw = commissionCents(grossCents, bps);
  return raw > pool ? pool : raw;
}

({int cents, int points}) _takePoints(
  int grossCents,
  int bps,
  int pool,
  int pointValueCents,
) {
  final centsRoom = _takeCents(grossCents, bps, pool);
  final points = pointsFromCents(centsRoom, pointValueCents);
  return (cents: centsFromPoints(points, pointValueCents), points: points);
}

void _requirePointValue(int pointValueCents) {
  if (pointValueCents <= 0) {
    throw ArgumentError('O ponto precisa valer ao menos um centavo.');
  }
}

String? _digits(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return digits;
}

/// Documento inteiro. Asterisco é máscara do Asaas e não serve para comparar.
String? _fullDocument(String? value) {
  if (value == null || value.contains('*')) return null;
  final digits = _digits(value);
  if (digits == null) return null;
  if (digits.length == 11 || digits.length == 14) return digits;
  return null;
}
