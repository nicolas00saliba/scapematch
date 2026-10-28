import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/groups/data/selected_game_type_store.dart';

/// Store do tipo de jogo. O `main` carrega o valor salvo antes do primeiro
/// frame. Sem override, a escolha é Todos.
final selectedGameTypeStoreProvider = Provider<SelectedGameTypeStore>(
  (ref) => SelectedGameTypeStore(),
);

/// Tipo de jogo atual. Filtra a janela de grupos, as novidades e as salas.
class SelectedGameTypeController extends Notifier<String> {
  @override
  String build() => ref.watch(selectedGameTypeStoreProvider).resolve();

  void select(String gameTypeId) {
    if (state == gameTypeId) {
      return;
    }
    state = gameTypeId;
    final store = ref.read(selectedGameTypeStoreProvider);
    store.remember(gameTypeId);
    unawaited(store.persist(gameTypeId));
  }
}

final selectedGameTypeIdProvider =
    NotifierProvider<SelectedGameTypeController, String>(
      SelectedGameTypeController.new,
    );
