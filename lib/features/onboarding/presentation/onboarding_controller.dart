import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';

/// Store da introdução. O `main` carrega o valor salvo antes do primeiro
/// frame. Sem override, a introdução ainda não foi vista.
final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  return OnboardingStore();
});

/// Se a introdução já foi concluída ou pulada neste aparelho.
final onboardingSeenProvider = NotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() => ref.watch(onboardingStoreProvider).seen;

  Future<void> markSeen() async {
    await ref.read(onboardingStoreProvider).markSeen();
    state = true;
  }
}
