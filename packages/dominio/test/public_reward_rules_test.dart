import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('a rpc publica vira a prévia da próxima indicação', () async {
    final rules = PublicRewardRules.fromJson({
      'updated_at': '2026-11-24T18:00:00Z',
      'c2c_from_bps': 150,
      'c2c_mid_active': 5,
      'c2c_mid_bps': 250,
      'c2c_high_active': 8,
      'c2c_high_bps': 500,
      'c2b_bps': 400,
      'point_value_cents': 1,
    });
    expect(rules.c2cRateBps(1), 150);
    expect(rules.previewC2cCents(10000, 1), 150);
    expect(rules.toRates().c2bBps, 400);
    expect(rules.updatedAt, DateTime.utc(2026, 11, 24, 18));

    final kept = await resolveRewardRules(
      current: rules,
      fetch: () async => throw StateError('sem rede'),
    );
    expect(kept, rules);

    final next = await resolveRewardRules(
      current: PublicRewardRules.fallback,
      fetch: () async => rules,
    );
    expect(next.c2cFromBps, 150);
    expect(PublicRewardRules.fallback.c2cFromBps, 100);
  });
}
