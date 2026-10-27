import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/cities/data/selected_city_store.dart';

/// Store da cidade. O `main` carrega o valor salvo antes do primeiro frame
/// e coloca a instância aqui. Sem override, não há cidade salva e a tela
/// usa Curitiba.
final selectedCityStoreProvider = Provider<SelectedCityStore>(
  (ref) => SelectedCityStore(),
);

/// Cidade atual do seletor.
///
/// Nunca começa vazia. Sem escolha salva, o valor é Curitiba. Uma escolha
/// gravada prevalece, porque o store já foi carregado antes do `runApp`.
class SelectedCityController extends Notifier<String> {
  @override
  String build() => ref.watch(selectedCityStoreProvider).resolve();

  void select(String cityId) {
    if (state == cityId) {
      return;
    }
    state = cityId;
    final store = ref.read(selectedCityStoreProvider);
    store.remember(cityId);
    unawaited(store.persist(cityId));
  }
}

final selectedCityIdProvider = NotifierProvider<SelectedCityController, String>(
  SelectedCityController.new,
);
