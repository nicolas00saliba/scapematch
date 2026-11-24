/// Carteira de Scape Points. 1 ponto vale [pointValueCents] centavos.
class ScapeWallet {
  const ScapeWallet({
    required this.referralCode,
    required this.availablePoints,
    required this.pendingPoints,
    required this.pointValueCents,
    required this.attributed,
    required this.canClaim,
    required this.entries,
    this.redeemMinPoints = 0,
    this.tier = 'nenhum',
    this.tierBps = 0,
    this.activeReferrals = 0,
    this.silverAt = 5,
    this.goldAt = 8,
    this.backedPoints = 0,
    this.unbackedPoints = 0,
    this.freeSlotEnabled = false,
    this.freeSlotMonthlyLimit = 0,
    this.freeSlotsUsedThisMonth = 0,
  });

  final String referralCode;
  final int availablePoints;
  final int pendingPoints;
  final int pointValueCents;
  final bool attributed;
  final bool canClaim;
  final List<ScapePointEntry> entries;
  final int redeemMinPoints;
  final String tier;

  /// Taxa absoluta da indicação de pessoas, em basis points, vinda do servidor.
  final int tierBps;
  final int activeReferrals;

  /// Indicados ativos para a taxa do meio. O nome antigo do campo é silver_at.
  final int silverAt;

  /// Indicados ativos para a taxa alta. O nome antigo do campo é gold_at.
  final int goldAt;
  final int backedPoints;
  final int unbackedPoints;
  final bool freeSlotEnabled;
  final int freeSlotMonthlyLimit;
  final int freeSlotsUsedThisMonth;

  String get tierLabel =>
      tierBps > 0 ? formatBasisPoints(tierBps) : 'sem indicado ativo';

  double get levelProgress {
    if (goldAt <= 0) return 0;
    final value = activeReferrals / goldAt;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  String get tierProgress {
    if (activeReferrals >= goldAt && goldAt > 0) {
      return 'Comissão atual $tierLabel. Este é o nível mais alto.';
    }
    if (activeReferrals >= silverAt) {
      final left = goldAt - activeReferrals;
      return 'Comissão atual $tierLabel. Faltam $left indicados ativos para o próximo nível.';
    }
    if (activeReferrals >= 1) {
      final left = silverAt - activeReferrals;
      return 'Comissão atual $tierLabel. Faltam $left indicados ativos para o próximo nível.';
    }
    return 'Falta 1 indicado ativo para começar a ganhar comissão.';
  }

  int get availableCents => availablePoints * pointValueCents;
  int get pendingCents => pendingPoints * pointValueCents;

  static const sample = ScapeWallet(
    referralCode: 'SCAPEDEMO',
    availablePoints: 1800,
    pendingPoints: 250,
    pointValueCents: 1,
    attributed: false,
    canClaim: false,
    tier: 'nivel_1',
    tierBps: 100,
    activeReferrals: 2,
    silverAt: 5,
    goldAt: 8,
    entries: [
      ScapePointEntry(
        kind: 'accrual',
        program: 'cashback',
        points: 100,
        amountCents: 100,
      ),
      ScapePointEntry(
        kind: 'accrual',
        program: 'c2c',
        points: 250,
        amountCents: 250,
      ),
      ScapePointEntry(
        kind: 'release',
        program: 'c2c',
        points: 1800,
        amountCents: 1800,
      ),
      ScapePointEntry(
        kind: 'redemption',
        program: 'redeem',
        points: 500,
        amountCents: 500,
      ),
    ],
  );

  factory ScapeWallet.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    return ScapeWallet(
      referralCode: json['referral_code']?.toString() ?? '',
      availablePoints: _intOf(json['available_points']),
      pendingPoints: _intOf(json['pending_points']),
      pointValueCents: _intOf(json['point_value_cents'], fallback: 1),
      attributed: json['attributed'] == true,
      canClaim: json['can_claim'] == true,
      entries: [
        if (rawEntries is List)
          for (final item in rawEntries)
            if (item is Map)
              ScapePointEntry.fromJson(Map<String, dynamic>.from(item)),
      ],
      redeemMinPoints: _intOf(json['redeem_min_points']),
      tier: json['tier']?.toString() ?? 'nenhum',
      tierBps: _intOf(json['tier_bps'] ?? json['tier_bonus_bps']),
      activeReferrals: _intOf(json['active_referrals']),
      silverAt: _intOf(json['silver_at'], fallback: 5),
      goldAt: _intOf(json['gold_at'], fallback: 8),
      backedPoints: _intOf(json['backed_points']),
      unbackedPoints: _intOf(json['unbacked_points']),
      freeSlotEnabled: json['backed_full_slot_enabled'] == true,
      freeSlotMonthlyLimit: _intOf(
        json['free_slot_monthly_limit'],
      ),
      freeSlotsUsedThisMonth: _intOf(json['free_slots_used_this_month']),
    );
  }
}

class ScapePointEntry {
  const ScapePointEntry({
    required this.kind,
    required this.points,
    required this.amountCents,
    this.program,
    this.createdAt,
    this.reviewStatus,
    this.drawnBps,
    this.doubled = false,
  });

  final String kind;
  final String? program;
  final int points;
  final int amountCents;
  final DateTime? createdAt;
  final String? reviewStatus;
  final int? drawnBps;
  final bool doubled;

  factory ScapePointEntry.fromJson(Map<String, dynamic> json) {
    final rawDate = json['created_at']?.toString();
    return ScapePointEntry(
      kind: json['kind']?.toString() ?? '',
      program: json['program']?.toString(),
      points: _intOf(json['points']),
      amountCents: _intOf(json['amount_cents']),
      createdAt: rawDate == null ? null : DateTime.tryParse(rawDate),
      reviewStatus: json['review_status']?.toString(),
      drawnBps: json['drawn_bps'] == null ? null : _intOf(json['drawn_bps']),
      doubled: json['doubled'] == true,
    );
  }

  String get title {
    if (reviewStatus == 'em_revisao') return 'Indicação em revisão';
    return switch (kind) {
      'accrual' => switch (program) {
        'c2c' => 'Indicação de jogador',
        'c2b' => 'Indicação de casa',
        'cashback' =>
          drawnBps == null
              ? 'Cashback'
              : 'Cashback ${formatBasisPoints(drawnBps!)}${doubled ? ' em dobro' : ''}',
        'welcome' => 'Boas-vindas',
        'passport' => 'Passaporte de salas',
        _ => 'Pontos a liberar',
      },
      'release' =>
        program == 'passport' ? 'Passaporte liberado' : 'Pontos liberados',
      'reversal' => switch (program) {
        'cashback' => 'Estorno do cashback',
        'passport' => 'Estorno do passaporte',
        _ => 'Estorno da indicação',
      },
      'redemption' => 'Pagamento de sala',
      'redemption_reversal' => 'Devolução de pontos',
      _ => 'Lançamento',
    };
  }

  String get detail {
    return switch (kind) {
      'accrual' =>
        reviewStatus == 'em_revisao'
            ? 'Aguardando conferência. Ainda não fica disponível.'
            : program == 'cashback'
            ? 'Do que você pagou nesta reserva. Fica pendente por 30 dias.'
            : program == 'passport'
            ? 'Marco do passaporte. Vira desconto, até o teto. Não paga a vaga inteira.'
            : 'Ficam pendentes por 30 dias.',
      'release' =>
        program == 'passport'
            ? 'Disponíveis como desconto, até o teto do resgate.'
            : 'Disponíveis para pagar sala.',
      'reversal' => 'O pagamento da reserva foi estornado.',
      'redemption' => 'Abatidos da sua parte. A casa recebe o valor cheio.',
      'redemption_reversal' => 'A cobrança não foi concluída.',
      _ => '',
    };
  }

  bool get adds => kind == 'accrual' || kind == 'redemption_reversal';
}

class PointSpendChoice {
  PointSpendChoice({
    required this.points,
    required this.subsidyCents,
    required this.chargedCents,
    this.discountCents = 0,
    this.cashbackMinBps = 50,
    this.cashbackMaxBps = 500,
    this.redeemMinPoints = 0,
    this.redeemMaxBps = 10000,
    this.maxPoints = 0,
    this.pointsOnly = false,
  });

  int points;
  int subsidyCents;
  int chargedCents;
  int discountCents;
  final int cashbackMinBps;
  final int cashbackMaxBps;
  final int redeemMinPoints;
  final int redeemMaxBps;
  int maxPoints;
  bool pointsOnly;
  var use = false;

  int get selected => use && points > 0 ? points : 0;

  void applyQuote(Map<String, dynamic> json) {
    points = _intOf(json['points']);
    subsidyCents = _intOf(json['subsidy_cents']);
    chargedCents = _intOf(json['charged_cents']);
    discountCents = _intOf(json['first_booking_discount_cents']);
    pointsOnly = json['points_only'] == true;
    final quotedMax = _intOf(json['max_points']);
    if (quotedMax > maxPoints) maxPoints = quotedMax;
    if (points > maxPoints) maxPoints = points;
  }

  factory PointSpendChoice.fromQuote(Map<String, dynamic> json) {
    final choice = PointSpendChoice(
      points: 0,
      subsidyCents: 0,
      chargedCents: 0,
      cashbackMinBps: _intOf(json['cashback_min_bps'], fallback: 50),
      cashbackMaxBps: _intOf(json['cashback_max_bps'], fallback: 500),
      redeemMinPoints: _intOf(json['redeem_min_points']),
      redeemMaxBps: _intOf(json['redeem_max_bps'], fallback: 10000),
    );
    choice.applyQuote(json);
    return choice;
  }
}

class ScapeLiability {
  const ScapeLiability({
    required this.unusedPoints,
    required this.unusedCents,
    required this.pendingPoints,
    required this.availablePoints,
    required this.venueCreditPendingCents,
  });

  final int unusedPoints;
  final int unusedCents;
  final int pendingPoints;
  final int availablePoints;
  final int venueCreditPendingCents;

  factory ScapeLiability.fromJson(Map<String, dynamic> json) {
    return ScapeLiability(
      unusedPoints: _intOf(json['unused_points']),
      unusedCents: _intOf(json['unused_cents']),
      pendingPoints: _intOf(json['pending_points']),
      availablePoints: _intOf(json['available_points']),
      venueCreditPendingCents: _intOf(json['venue_credit_pending_cents']),
    );
  }
}

int _intOf(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? fallback;
}

String formatBasisPoints(int bps) {
  final whole = bps ~/ 100;
  final frac = (bps.abs() % 100)
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  if (frac.isEmpty) return '$whole%';
  return '$whole,$frac%';
}

String formatPoints(int points) {
  final negative = points < 0;
  final digits = points.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
