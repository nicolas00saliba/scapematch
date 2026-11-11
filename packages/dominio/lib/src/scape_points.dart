import 'package:dominio/src/commission.dart';

/// Regras do Modelo 2. Os números abaixo são o padrão aprovado;
/// o banco guarda a mesma tabela e pode mudá-la sem recompilar o app.
///
/// 1 Scape Point vale [ReferralRates.pointValueCents] centavos.
/// O padrão é 1 ponto = R\$ 0,01. O ponto não vence e não saca:
/// só abate sala. A casa continua recebendo o líquido cheio;
/// o abatimento sai da comissão da EscapeMatch.
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
    this.redeemMinPoints = 1000,
    this.redeemMaxBps = 3000,
    this.backedFullSlotEnabled = false,
    this.freeSlotMonthlyLimit = 1,
    this.blockSelfPayer = true,
    this.payerReferredAccountCap = 3,
    this.sameDeviceReviewThreshold = 2,
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

  /// O pagador é o próprio indicador: aquela indicação não é lançada.
  final bool blockSelfPayer;

  /// Contas indicadas distintas que o mesmo pagador pode premiar. 0 desliga.
  final int payerReferredAccountCap;

  /// Contas do mesmo indicador no mesmo aparelho a partir deste número
  /// ficam em revisão. 0 desliga.
  final int sameDeviceReviewThreshold;

  /// Mínimo de pontos para usar o saldo numa reserva.
  final int redeemMinPoints;

  /// Teto da reserva que pode ser pago com pontos, em basis points.
  /// Vale para pontos sem lastro e, com a flag desligada, para todos.
  final int redeemMaxBps;

  /// Pontos de indicação já liberados podem cobrir a vaga inteira.
  /// Nasce desligado. Boas-vindas, cashback e promoção continuam no teto.
  final bool backedFullSlotEnabled;

  /// Vagas em que a EscapeMatch completa o líquido da casa, por jogador
  /// e por mês. Zero desliga essa extensão mesmo com a flag ligada.
  final int freeSlotMonthlyLimit;

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
    this.reviewStatus,
  });

  /// `cashback`, `c2c`, `b2c`, `c2b` ou `b2b`.
  final String program;
  final int cents;
  final int points;
  final RewardPayee payee;

  /// `em_revisao` quando a conta veio do mesmo aparelho que outra do indicador.
  final String? reviewStatus;

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
    this.playerPayerIsReferrer = false,
    this.venuePayerIsReferrer = false,
    this.payerRewardedAccounts = 0,
    this.playerSubjectAlreadyRewarded = false,
    this.venueSubjectAlreadyRewarded = false,
    this.playerDeviceCluster = 0,
    this.venueDeviceCluster = 0,
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

  /// O documento ou o cartão de quem pagou é o do indicador do jogador.
  final bool playerPayerIsReferrer;

  /// O documento ou o cartão de quem pagou é o do indicador da casa.
  final bool venuePayerIsReferrer;

  /// Outras contas indicadas que este pagador já premiou.
  final int payerRewardedAccounts;

  final bool playerSubjectAlreadyRewarded;
  final bool venueSubjectAlreadyRewarded;

  /// Contas deste indicador criadas no mesmo aparelho, incluindo esta.
  final int playerDeviceCluster;
  final int venueDeviceCluster;
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
    this.backedPoints = 0,
    this.unbackedPoints = 0,
    this.topupCents = 0,
    this.pointsOnly = false,
    this.limitReason,
  });

  final int grossCents;
  final int chargedCents;
  final int subsidyCents;
  final int points;
  final int houseNetCents;
  final int commissionCents;

  /// Nulo quando não há abatimento: o split percentual antigo continua.
  /// Com abatimento que ainda cabe na cobrança, é o percentual (até 4 casas)
  /// que devolve o líquido cheio da casa sobre o valor menor.
  /// Nulo também na vaga grátis e quando o líquido não cabe: o que falta
  /// vai para [topupCents], no crédito da casa, e não para um split acima de 100%.
  final double? splitPercent;
  final int maxPoints;

  /// Pontos de indicação (c2c, c2b) usados nesta cotação.
  final int backedPoints;

  /// Boas-vindas, cashback e o restante sem lastro.
  final int unbackedPoints;

  /// Centavos do líquido da casa que não cabem na cobrança.
  /// Saem do lastro da EscapeMatch e esperam o próximo repasse da casa.
  final int topupCents;

  /// A vaga inteira foi coberta. Não há cobrança no Asaas.
  final bool pointsOnly;

  /// `monthly_limit`, `antifraud` ou `reserve` quando a extensão não
  /// coube inteira. Nulo quando não houve corte da vaga grátis.
  final String? limitReason;
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

/// Pagamento por terceiro libera recompensa e desconto.
/// [payerStatus] fica no registro e não barra.
bool referralBenefitAllowed(String? payerStatus) {
  return payerStatus != 'blocked-by-removed-rule';
}

/// O desconto da primeira reserva não exige o CPF de quem pagou.
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

bool _payerBlocksReferral({
  required bool payerIsReferrer,
  required int rewardedAccounts,
  required bool subjectAlreadyRewarded,
  required ReferralRates rates,
}) {
  if (rates.blockSelfPayer && payerIsReferrer) return true;
  final cap = rates.payerReferredAccountCap;
  if (cap <= 0 || subjectAlreadyRewarded) return false;
  return rewardedAccounts >= cap;
}

String? _deviceReview(int cluster, ReferralRates rates) {
  final threshold = rates.sameDeviceReviewThreshold;
  if (threshold <= 0 || cluster < threshold) return null;
  return 'em_revisao';
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
  final playerReview = _deviceReview(input.playerDeviceCluster, rates);
  if (player != null &&
      attributionCovers(player, input.paidAt) &&
      !input.payerCpfMissing &&
      !_payerBlocksReferral(
        payerIsReferrer: input.playerPayerIsReferrer,
        rewardedAccounts: input.payerRewardedAccounts,
        subjectAlreadyRewarded: input.playerSubjectAlreadyRewarded,
        rates: rates,
      )) {
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
              reviewStatus: playerReview,
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
            reviewStatus: playerReview,
          ),
        );
        pool -= taken.cents;
      }
    }
  }

  final venue = input.fraudReason == null ? input.venueReferrer : null;
  final venueReview = _deviceReview(input.venueDeviceCluster, rates);
  if (venue != null &&
      attributionCovers(venue, input.paidAt) &&
      !_payerBlocksReferral(
        payerIsReferrer: input.venuePayerIsReferrer,
        rewardedAccounts: input.payerRewardedAccounts,
        subjectAlreadyRewarded: input.venueSubjectAlreadyRewarded,
        rates: rates,
      )) {
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
              reviewStatus: venueReview,
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
            reviewStatus: venueReview,
          ),
        );
      }
    }
  }

  return lines;
}

/// Quantas reservas de [grossCents] um indicado precisa pagar para quem
/// indicou juntar [targetPoints]. A taxa é a de jogador para jogador.
int referralBookingsForPoints({
  required int targetPoints,
  required int grossCents,
  int c2cBps = 250,
  int pointValueCents = 1,
}) {
  final each = pointsFromCents(
    commissionCents(grossCents, c2cBps),
    pointValueCents,
  );
  if (each <= 0) {
    throw ArgumentError('A indicação não gera ponto.');
  }
  if (targetPoints <= 0) return 0;
  return (targetPoints + each - 1) ~/ each;
}

/// Abate pontos do valor cobrado do jogador. O líquido da casa fica o do
/// preço cheio. O percentual novo só existe quando o líquido cabe na
/// cobrança; ele é arredondado para cima em 4 casas, que é o limite do Asaas.
///
/// Com [ReferralRates.backedFullSlotEnabled], pontos de indicação já
/// liberados ([availableBackedPoints]) podem cobrir a vaga inteira, até o
/// [reservedBalanceCents]. Esse saldo já entrou na comissão; a trava é não
/// deixá-lo negativo. O que passar da comissão não aumenta o split acima de
/// 100%: vira [PointSubsidyQuote.topupCents] e espera o próximo repasse da
/// casa. Boas-vindas e promoções continuam no teto de sempre.
/// [availableBackedPoints] nulo conta tudo como sem lastro.
/// [reservedBalanceCents] nulo usa o valor dos pontos de indicação do jogador.
PointSubsidyQuote quotePointSubsidy({
  required int grossCents,
  required int commissionBps,
  required int requestedPoints,
  required int availablePoints,
  int? availableBackedPoints,
  ReferralRates rates = ReferralRates.official,
  int receiptFeeCents = 0,
  int? reservedBalanceCents,
  int freeSlotsUsedThisMonth = 0,
  bool backedFraudHold = false,
}) {
  _requirePointValue(rates.pointValueCents);
  if (grossCents <= 0) {
    throw ArgumentError('A reserva precisa de um valor.');
  }
  if (receiptFeeCents < 0 || (reservedBalanceCents != null && reservedBalanceCents < 0)) {
    throw ArgumentError('A taxa e o saldo reservado não podem ser negativos.');
  }
  final commission = commissionCents(grossCents, commissionBps);
  final houseNet = grossCents - commission;
  final classicCeiling = _classicMaxPoints(
    grossCents: grossCents,
    commission: commission,
    availablePoints: availablePoints,
    rates: rates,
  );
  final backedPool = _clampBacked(availableBackedPoints, availablePoints);
  final unbackedPool = availablePoints - backedPool;
  final extensionOff = !rates.backedFullSlotEnabled ||
      backedFraudHold ||
      rates.freeSlotMonthlyLimit <= 0 ||
      freeSlotsUsedThisMonth >= rates.freeSlotMonthlyLimit;
  if (extensionOff) {
    final reason = !rates.backedFullSlotEnabled
        ? null
        : backedFraudHold
        ? 'antifraud'
        : 'monthly_limit';
    return _classicQuote(
      grossCents: grossCents,
      commission: commission,
      houseNet: houseNet,
      requestedPoints: requestedPoints,
      availablePoints: availablePoints,
      maxPoints: classicCeiling,
      unbackedPool: unbackedPool,
      rates: rates,
      limitReason: reason,
    );
  }

  final fullPoints = pointsFromCents(grossCents, rates.pointValueCents);
  final reserved = reservedBalanceCents ??
      centsFromPoints(backedPool, rates.pointValueCents);
  final ceiling = _allocateFullSlot(
    want: availablePoints > fullPoints ? fullPoints : availablePoints,
    grossCents: grossCents,
    commission: commission,
    houseNet: houseNet,
    classicCeiling: classicCeiling,
    backedPool: backedPool,
    unbackedPool: unbackedPool,
    pointValue: rates.pointValueCents,
    receiptFeeCents: receiptFeeCents,
    openTopupCents: 0,
    platformCash: reserved,
    reserveCents: 0,
  );
  var maxPoints = ceiling.points;
  if (availablePoints < rates.redeemMinPoints ||
      maxPoints < rates.redeemMinPoints) {
    maxPoints = 0;
  }
  final applied = _allocateFullSlot(
    want: requestedPoints,
    grossCents: grossCents,
    commission: commission,
    houseNet: houseNet,
    classicCeiling: classicCeiling,
    backedPool: backedPool,
    unbackedPool: unbackedPool,
    pointValue: rates.pointValueCents,
    receiptFeeCents: receiptFeeCents,
    openTopupCents: 0,
    platformCash: reserved,
    reserveCents: 0,
  );
  var points = applied.points;
  var backedSpend = applied.backedSpend;
  var unbackedSpend = applied.unbackedSpend;
  var topup = applied.topup;
  if (points > maxPoints || points < rates.redeemMinPoints) {
    points = 0;
    backedSpend = 0;
    unbackedSpend = 0;
    topup = 0;
  }
  final subsidy = centsFromPoints(points, rates.pointValueCents);
  final charged = grossCents - subsidy;
  return PointSubsidyQuote(
    grossCents: grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points: points,
    houseNetCents: houseNet,
    commissionCents: commission,
    splitPercent: _splitFor(houseNet, charged, subsidy, topup),
    maxPoints: maxPoints,
    backedPoints: backedSpend,
    unbackedPoints: unbackedSpend,
    topupCents: topup,
    pointsOnly: charged == 0 && subsidy > 0,
    limitReason: applied.reserveCut ? 'reserve' : null,
  );
}

int _classicMaxPoints({
  required int grossCents,
  required int commission,
  required int availablePoints,
  required ReferralRates rates,
}) {
  final room = grossCents > 1 ? grossCents - 1 : 0;
  final percentCap = commissionCents(grossCents, rates.redeemMaxBps);
  final maxSubsidy = [
    commission,
    room,
    percentCap < 0 ? 0 : percentCap,
  ].reduce((a, b) => a < b ? a : b);
  var maxPoints = pointsFromCents(
    maxSubsidy < 0 ? 0 : maxSubsidy,
    rates.pointValueCents,
  );
  if (availablePoints < rates.redeemMinPoints ||
      maxPoints < rates.redeemMinPoints) {
    maxPoints = 0;
  }
  return maxPoints;
}

PointSubsidyQuote _classicQuote({
  required int grossCents,
  required int commission,
  required int houseNet,
  required int requestedPoints,
  required int availablePoints,
  required int maxPoints,
  required int unbackedPool,
  required ReferralRates rates,
  required String? limitReason,
}) {
  var points = requestedPoints;
  if (points < 0) points = 0;
  if (points > availablePoints) points = availablePoints;
  if (points > maxPoints) points = maxPoints;
  if (points < rates.redeemMinPoints) points = 0;
  var unbackedSpend = points > unbackedPool ? unbackedPool : points;
  if (unbackedSpend < 0) unbackedSpend = 0;
  final backedSpend = points - unbackedSpend;
  final subsidy = centsFromPoints(points, rates.pointValueCents);
  final charged = grossCents - subsidy;
  return PointSubsidyQuote(
    grossCents: grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points: points,
    houseNetCents: houseNet,
    commissionCents: commission,
    splitPercent: subsidy == 0
        ? null
        : subsidizedHouseSplitPercent(
            houseNetCents: houseNet,
            chargedCents: charged,
          ),
    maxPoints: maxPoints,
    backedPoints: backedSpend,
    unbackedPoints: unbackedSpend,
    limitReason: limitReason,
  );
}

int _clampBacked(int? availableBackedPoints, int availablePoints) {
  var backed = availableBackedPoints ?? 0;
  if (backed < 0) backed = 0;
  if (backed > availablePoints) backed = availablePoints;
  return backed;
}

double? _splitFor(int houseNet, int charged, int subsidy, int topup) {
  if (subsidy == 0 || charged <= 0 || topup > 0) return null;
  return subsidizedHouseSplitPercent(
    houseNetCents: houseNet,
    chargedCents: charged,
  );
}

class _FullAllocation {
  const _FullAllocation({
    required this.points,
    required this.backedSpend,
    required this.unbackedSpend,
    required this.topup,
    required this.reserveCut,
  });

  final int points;
  final int backedSpend;
  final int unbackedSpend;
  final int topup;
  final bool reserveCut;
}

_FullAllocation _allocateFullSlot({
  required int want,
  required int grossCents,
  required int commission,
  required int houseNet,
  required int classicCeiling,
  required int backedPool,
  required int unbackedPool,
  required int pointValue,
  required int receiptFeeCents,
  required int openTopupCents,
  required int platformCash,
  required int reserveCents,
}) {
  if (want < 0) want = 0;
  final pool = backedPool + unbackedPool;
  if (want > pool) want = pool;
  final unbackedCap = classicCeiling < unbackedPool
      ? classicCeiling
      : unbackedPool;
  var unbackedSpend = want < unbackedCap ? want : unbackedCap;
  if (unbackedSpend < 0) unbackedSpend = 0;
  var backedSpend = want - unbackedSpend;
  if (backedSpend > backedPool) backedSpend = backedPool;
  if (backedSpend < 0) backedSpend = 0;
  var reserveCut = false;
  final room = platformCash - openTopupCents - reserveCents;
  while (backedSpend >= 0) {
    final subsidy = centsFromPoints(unbackedSpend + backedSpend, pointValue);
    final charged = grossCents - subsidy;
    if (charged < 0) {
      backedSpend -= 1;
      continue;
    }
    final fee = charged == 0
        ? 0
        : (receiptFeeCents > charged ? charged : receiptFeeCents);
    final net = charged - fee;
    if (charged > 0 && net <= 0) {
      if (backedSpend == 0) break;
      backedSpend -= 1;
      continue;
    }
    final topup = charged == 0 ? houseNet : (houseNet > net ? houseNet - net : 0);
    if (backedSpend == 0) {
      return _FullAllocation(
        points: unbackedSpend,
        backedSpend: 0,
        unbackedSpend: unbackedSpend,
        topup: 0,
        reserveCut: reserveCut,
      );
    }
    if (topup > backedSpend * pointValue || backedSpend * pointValue > room) {
      reserveCut = true;
      if (backedSpend == 0) break;
      backedSpend -= 1;
      continue;
    }
    if (topup > 0 && topup > room) {
      reserveCut = true;
      if (backedSpend == 0) break;
      backedSpend -= 1;
      continue;
    }
    return _FullAllocation(
      points: unbackedSpend + backedSpend,
      backedSpend: backedSpend,
      unbackedSpend: unbackedSpend,
      topup: topup,
      reserveCut: reserveCut,
    );
  }
  return _FullAllocation(
    points: unbackedSpend,
    backedSpend: 0,
    unbackedSpend: unbackedSpend,
    topup: 0,
    reserveCut: reserveCut,
  );
}

/// Percentual do valor cobrado (já com abatimento) que devolve o líquido
/// cheio da casa. Sobe na 4ª casa decimal para a casa não perder centavo
/// por arredondamento. O Asaas aplica esse percentual sobre o líquido
/// depois da taxa dele; o centavo que sobrar sai da EscapeMatch.
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
