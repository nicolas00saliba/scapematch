import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/app/scapematch_app.dart';
import 'package:scapematch/app/url_strategy.dart';
import 'package:scapematch/features/auth/data/pending_invite_store.dart';
import 'package:scapematch/features/cities/data/selected_city_store.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/data/selected_game_type_store.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch/providers/repositories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootScapeBackend();
  configureUrlStrategy();
  // The handle is intentionally not disposed: semantics stay on so screen
  // readers and the web accessibility tree can see the controls.
  SemanticsBinding.instance.ensureSemantics();
  await initializeDateFormatting('pt_BR');
  // A cidade entra no primeiro frame. Sem isso, a Home pisca o aviso de
  // “escolha a cidade” antes de ler o que foi salvo.
  final cityStore = SelectedCityStore();
  final gameTypeStore = SelectedGameTypeStore();
  // A demonstração não grava a chave: real e demo dividem o localStorage.
  final onboarding = OnboardingStore(persist: kAppMode == AppMode.real);
  final pendingInvites = PendingInviteStore();
  final themeStore = ThemeChoiceStore();
  await cityStore.load();
  await gameTypeStore.load();
  await onboarding.load();
  await themeStore.load();
  // Sem este load, recarregar a página entre Participar e o cadastro
  // cria um store vazio e a pessoa não entra no grupo.
  await pendingInvites.load();
  runApp(
    ProviderScope(
      // The screens already offer "Tentar de novo". A background retry
      // would hide the error state the user is supposed to see.
      retry: noAutomaticRetry,
      overrides: [
        selectedCityStoreProvider.overrideWithValue(cityStore),
        selectedGameTypeStoreProvider.overrideWithValue(gameTypeStore),
        onboardingStoreProvider.overrideWithValue(onboarding),
        pendingInviteStoreProvider.overrideWithValue(pendingInvites),
        themeChoiceStoreProvider.overrideWithValue(themeStore),
      ],
      child: const ScapeMatchApp(),
    ),
  );
}
