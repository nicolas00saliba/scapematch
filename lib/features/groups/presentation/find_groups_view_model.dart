import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/providers/repositories.dart';

/// Texto da busca compacta da Home. Não dispara outra ida ao repositório.
///
/// AutoDispose: a busca zera quando a Home sai da árvore. Trocar para a aba
/// Meus grupos não apaga o texto, porque o shell mantém a Home montada. O
/// campo e este provider somem juntos.
class GroupSearchController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    if (state == value) {
      return;
    }
    state = value;
  }
}

final groupSearchQueryProvider =
    NotifierProvider.autoDispose<GroupSearchController, String>(
      GroupSearchController.new,
    );

/// Lista da cidade.
///
/// A busca por texto fica em [filteredGroupsProvider], para cada letra não
/// esperar de novo o repositório.
class FindGroupsViewModel extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() {
    final cityId = ref.watch(selectedCityIdProvider);
    return ref.watch(groupRepositoryProvider).listByCity(cityId);
  }
}

final findGroupsViewModelProvider =
    AsyncNotifierProvider.autoDispose<FindGroupsViewModel, List<Group>>(
      FindGroupsViewModel.new,
    );

/// A lista da cidade com o texto da busca aplicado em memória.
///
/// Também é autoDispose. Um provider comum seguraria
/// [groupSearchQueryProvider] vivo para sempre, e a Home recriada
/// mostraria a lista filtrada com o campo vazio.
final filteredGroupsProvider = Provider.autoDispose<AsyncValue<List<Group>>>((
  ref,
) {
  final query = ref.watch(groupSearchQueryProvider);
  final gameTypeId = ref.watch(selectedGameTypeIdProvider);
  return ref
      .watch(findGroupsViewModelProvider)
      .whenData(
        (groups) => filterGroupsByGameType(
          filterGroupsByText(groups, query),
          gameTypeId,
        ),
      );
});

/// Todos devolve a lista. Outro id fica só com os grupos daquele tipo.
List<Group> filterGroupsByGameType(List<Group> groups, String gameTypeId) {
  if (gameTypeId == GameTypes.all) {
    return groups;
  }
  return [
    for (final group in groups)
      if (group.gameType == gameTypeId) group,
  ];
}

/// Casa, sala ou bairro. Texto vazio devolve a mesma lista.
List<Group> filterGroupsByText(List<Group> groups, String query) {
  final text = query.trim().toLowerCase();
  if (text.isEmpty) {
    return groups;
  }
  return [
    for (final group in groups)
      if ('${group.roomName} ${group.houseName} ${group.neighborhood}'
          .toLowerCase()
          .contains(text))
        group,
  ];
}
