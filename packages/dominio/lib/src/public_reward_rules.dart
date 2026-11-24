import 'package:dominio/src/commission.dart';
import 'package:dominio/src/scape_points.dart';

/// Regras que o app pode mostrar. Só o que a RPC pública devolve.
///
/// O padrão é o último recurso, quando não há cache nem rede. O banco
/// é quem vale. Um pedido já criado no PagBank não lê esta classe de novo:
/// o split foi gravado na cobrança.
class PublicRewardRules {
  const PublicRewardRules({
    this.updatedAt,
    this.c2cFromBps = 100,
    this.c2cMidActive = 5,
    this.c2cMidBps = 250,
    this.c2cHighActive = 8,
    this.c2cHighBps = 500,
    this.c2bBps = 500,
    this.b2cBps = 500,
    this.b2bBps = 500,
    this.pointValueCents = 1,
    this.firstBookingDiscountBps = 2000,
    this.redeemMaxBps = 10000,
    this.cashbackMinBps = 50,
    this.cashbackMaxBps = 500,
  });

  /// Último recurso. A tela usa o cache ou a RPC antes disto.
  static const fallback = PublicRewardRules();

  /// Versão da linha. O app recarrega quando este instante muda.
  final DateTime? updatedAt;
  final int c2cFromBps;
  final int c2cMidActive;
  final int c2cMidBps;
  final int c2cHighActive;
  final int c2cHighBps;
  final int c2bBps;
  final int b2cBps;
  final int b2bBps;
  final int pointValueCents;
  final int firstBookingDiscountBps;
  final int redeemMaxBps;
  final int cashbackMinBps;
  final int cashbackMaxBps;

  /// Taxa absoluta da indicação de pessoas. Zero sem indicado ativo.
  int c2cRateBps(int activeReferrals) {
    if (activeReferrals >= c2cHighActive) return c2cHighBps;
    if (activeReferrals >= c2cMidActive) return c2cMidBps;
    if (activeReferrals >= 1) return c2cFromBps;
    return 0;
  }

  /// Prévia, em centavos, da indicação de pessoas sobre [grossCents].
  /// A mesma conta do servidor: meio centavo sobe.
  int previewC2cCents(int grossCents, int activeReferrals) {
    return commissionCents(grossCents, c2cRateBps(activeReferrals));
  }

  /// Campos que a cotação local já conhece. Travas de antifraude ficam
  /// no padrão do código: a RPC pública não as entrega.
  ReferralRates toRates() {
    return ReferralRates(
      b2cBps: b2cBps,
      c2bBps: c2bBps,
      b2bBps: b2bBps,
      c2cFromBps: c2cFromBps,
      c2cMidActive: c2cMidActive,
      c2cMidBps: c2cMidBps,
      c2cHighActive: c2cHighActive,
      c2cHighBps: c2cHighBps,
      pointValueCents: pointValueCents,
      firstBookingDiscountBps: firstBookingDiscountBps,
      redeemMaxBps: redeemMaxBps,
    );
  }

  factory PublicRewardRules.fromJson(Map<String, dynamic> json) {
    final rawAt = json['updated_at']?.toString();
    return PublicRewardRules(
      updatedAt: rawAt == null ? null : DateTime.tryParse(rawAt),
      c2cFromBps: _int(json['c2c_from_bps'], 100),
      c2cMidActive: _int(json['c2c_mid_active'], 5),
      c2cMidBps: _int(json['c2c_mid_bps'], 250),
      c2cHighActive: _int(json['c2c_high_active'], 8),
      c2cHighBps: _int(json['c2c_high_bps'], 500),
      c2bBps: _int(json['c2b_bps'], 500),
      b2cBps: _int(json['b2c_bps'], 500),
      b2bBps: _int(json['b2b_bps'], 500),
      pointValueCents: _int(json['point_value_cents'], 1),
      firstBookingDiscountBps: _int(json['first_booking_discount_bps'], 2000),
      redeemMaxBps: _int(json['redeem_max_bps'], 10000),
      cashbackMinBps: _int(json['cashback_min_bps'], 50),
      cashbackMaxBps: _int(json['cashback_max_bps'], 500),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'c2c_from_bps': c2cFromBps,
      'c2c_mid_active': c2cMidActive,
      'c2c_mid_bps': c2cMidBps,
      'c2c_high_active': c2cHighActive,
      'c2c_high_bps': c2cHighBps,
      'c2b_bps': c2bBps,
      'b2c_bps': b2cBps,
      'b2b_bps': b2bBps,
      'point_value_cents': pointValueCents,
      'first_booking_discount_bps': firstBookingDiscountBps,
      'redeem_max_bps': redeemMaxBps,
      'cashback_min_bps': cashbackMinBps,
      'cashback_max_bps': cashbackMaxBps,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PublicRewardRules &&
        other.updatedAt == updatedAt &&
        other.c2cFromBps == c2cFromBps &&
        other.c2cMidActive == c2cMidActive &&
        other.c2cMidBps == c2cMidBps &&
        other.c2cHighActive == c2cHighActive &&
        other.c2cHighBps == c2cHighBps &&
        other.c2bBps == c2bBps &&
        other.b2cBps == b2cBps &&
        other.b2bBps == b2bBps &&
        other.pointValueCents == pointValueCents &&
        other.firstBookingDiscountBps == firstBookingDiscountBps &&
        other.redeemMaxBps == redeemMaxBps &&
        other.cashbackMinBps == cashbackMinBps &&
        other.cashbackMaxBps == cashbackMaxBps;
  }

  @override
  int get hashCode => Object.hash(
    updatedAt,
    c2cFromBps,
    c2cMidActive,
    c2cMidBps,
    c2cHighActive,
    c2cHighBps,
    c2bBps,
    b2cBps,
    b2bBps,
    pointValueCents,
    firstBookingDiscountBps,
    redeemMaxBps,
    cashbackMinBps,
    cashbackMaxBps,
  );
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? fallback;
}

/// Aplica a leitura. Rede vazia ou falha deixa [current], que é o cache
/// ou, se nunca houve cache, o padrão do código.
Future<PublicRewardRules> resolveRewardRules({
  required PublicRewardRules current,
  required Future<PublicRewardRules?> Function() fetch,
}) async {
  try {
    final next = await fetch();
    return next ?? current;
  } on Object {
    return current;
  }
}
