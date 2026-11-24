import 'package:dominio/dominio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/data/reward_rules_store.dart';

/// De onde vem a regra vigente. Teste troca isto. O app real chama a RPC.
abstract class RewardRulesSource {
  Future<PublicRewardRules?> fetch();
}

class SupabaseRewardRulesSource implements RewardRulesSource {
  @override
  Future<PublicRewardRules?> fetch() async {
    if (!scapeUsesLiveBackend) return null;
    final data = await scapeSupabase.rpc('reward_rules_public');
    if (data is Map) {
      return PublicRewardRules.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }
}

final rewardRulesStoreProvider = Provider<RewardRulesStore>(
  (ref) => RewardRulesStore(),
);

final rewardRulesSourceProvider = Provider<RewardRulesSource>(
  (ref) => SupabaseRewardRulesSource(),
);

/// Regra que a tela mostra. Começa no cache (ou no padrão) e a troca
/// quando a RPC devolve uma versão nova.
class RewardRulesController extends Notifier<PublicRewardRules> {
  @override
  PublicRewardRules build() => ref.watch(rewardRulesStoreProvider).current;

  Future<void> refresh() async {
    final store = ref.read(rewardRulesStoreProvider);
    final next = await resolveRewardRules(
      current: state,
      fetch: ref.read(rewardRulesSourceProvider).fetch,
    );
    if (next == state) return;
    state = next;
    await store.save(next);
  }
}

final rewardRulesProvider =
    NotifierProvider<RewardRulesController, PublicRewardRules>(
      RewardRulesController.new,
    );
