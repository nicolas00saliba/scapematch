import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/domain/theme_choice.dart';

/// Store do tema. O `main` carrega o valor salvo antes do primeiro frame.
final themeChoiceStoreProvider = Provider<ThemeChoiceStore>(
  (ref) => ThemeChoiceStore(),
);

/// Aparência atual. Sem escolha salva, segue o aparelho.
class ThemeChoiceController extends Notifier<ThemeChoice> {
  @override
  ThemeChoice build() => ref.watch(themeChoiceStoreProvider).choice;

  void select(ThemeChoice choice) {
    if (state == choice) {
      return;
    }
    state = choice;
    final store = ref.read(themeChoiceStoreProvider);
    store.remember(choice);
    unawaited(store.persist(choice));
  }
}

final themeChoiceProvider =
    NotifierProvider<ThemeChoiceController, ThemeChoice>(
      ThemeChoiceController.new,
    );
