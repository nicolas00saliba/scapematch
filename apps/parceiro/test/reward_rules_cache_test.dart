import 'package:dominio/dominio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scapematch/features/scape_points/data/reward_rules_store.dart';

void main() {
  test('o cache guarda a regra e a falha de rede não apaga', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RewardRulesStore();
    await store.load();
    expect(store.hasCache, isFalse);
    expect(store.current.c2cFromBps, 100);

    const rules = PublicRewardRules(
      c2cFromBps: 150,
      cashbackMinBps: 100,
      cashbackMaxBps: 400,
    );
    await store.save(rules);
    final again = RewardRulesStore();
    await again.load();
    expect(again.current.c2cFromBps, 150);
    expect(
      PartnerLegal.bodyFor(again.current),
      contains('de 1% a 4%'),
    );
    expect(PartnerLegal.bodyFor(PublicRewardRules.fallback), contains('de 0,5% a 5%'));
  });
}
