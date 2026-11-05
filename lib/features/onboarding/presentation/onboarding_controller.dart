import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/providers/repositories.dart';

/// Store da introdução. O `main` carrega o valor salvo antes do primeiro
/// frame. Sem override, a introdução ainda não foi vista.
final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  return OnboardingStore();
});

/// Modo que decide a introdução. Acompanha o plano do processo.
/// Um teste troca só isto, sem subir o Supabase.
final onboardingModeProvider = Provider<AppMode>((ref) {
  return ref.watch(backendPlanProvider).mode;
});

/// A primeira abertura do app real começa na introdução.
/// A demonstração entra direto na Home.
bool introIsFirstScreen({required AppMode mode, required bool seen}) {
  return mode == AppMode.real && !seen;
}

/// “Ver introdução” fica só na Ajuda da demonstração.
bool showsIntroReplay(AppMode mode) => mode == AppMode.demo;

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
