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
  });

  final String referralCode;
  final int availablePoints;
  final int pendingPoints;
  final int pointValueCents;
  final bool attributed;
  final bool canClaim;
  final List<ScapePointEntry> entries;

  int get availableCents => availablePoints * pointValueCents;
  int get pendingCents => pendingPoints * pointValueCents;

  static const sample = ScapeWallet(
    referralCode: 'SCAPEDEMO',
    availablePoints: 1800,
    pendingPoints: 250,
    pointValueCents: 1,
    attributed: false,
    canClaim: false,
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
  });

  final String kind;
  final String? program;
  final int points;
  final int amountCents;
  final DateTime? createdAt;

  factory ScapePointEntry.fromJson(Map<String, dynamic> json) {
    final rawDate = json['created_at']?.toString();
    return ScapePointEntry(
      kind: json['kind']?.toString() ?? '',
      program: json['program']?.toString(),
      points: _intOf(json['points']),
      amountCents: _intOf(json['amount_cents']),
      createdAt: rawDate == null ? null : DateTime.tryParse(rawDate),
    );
  }

  String get title {
    return switch (kind) {
      'accrual' => switch (program) {
        'c2c' => 'Indicação de jogador',
        'c2b' => 'Indicação de casa',
        'cashback' => 'Cashback',
        _ => 'Pontos a liberar',
      },
      'release' => 'Pontos liberados',
      'reversal' =>
        program == 'cashback' ? 'Estorno do cashback' : 'Estorno da indicação',
      'redemption' => 'Pagamento de sala',
      'redemption_reversal' => 'Devolução de pontos',
      _ => 'Lançamento',
    };
  }

  String get detail {
    return switch (kind) {
      'accrual' =>
        program == 'cashback'
            ? 'Do que você pagou nesta reserva. Fica pendente por 30 dias.'
            : 'Ficam pendentes por 30 dias.',
      'release' => 'Disponíveis para pagar sala.',
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
  });

  final int points;
  final int subsidyCents;
  final int chargedCents;
  var use = false;

  int get selected => use && points > 0 ? points : 0;

  factory PointSpendChoice.fromQuote(Map<String, dynamic> json) {
    return PointSpendChoice(
      points: _intOf(json['points']),
      subsidyCents: _intOf(json['subsidy_cents']),
      chargedCents: _intOf(json['charged_cents']),
    );
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
