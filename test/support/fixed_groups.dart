import 'package:flutter_riverpod/misc.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

import 'sample_clock.dart';

/// Lista fixa da Home. Não passa pelo cancelamento automático do repositório.
class FixedFindGroups extends FindGroupsViewModel {
  FixedFindGroups(this.items);

  final List<Group> items;

  @override
  Future<List<Group>> build() async => items;
}

List<Group> curitibaSampleGroups() {
  final database = buildSampleDatabase(now: sampleNow);
  return [
    for (final group in database.groups)
      if (group.cityId == SampleIds.curitiba) group,
  ];
}

/// Sessão já começou e ainda falta [missing] gente para fechar.
Group liveClosing(
  Group group, {
  int missing = 1,
  String? gameType,
  DateTime? startsAt,
}) {
  return group.copyWith(
    startsAt: startsAt ?? sampleNow.subtract(const Duration(minutes: 20)),
    filledSpots: group.totalSpots - missing,
    gameType: gameType ?? group.gameType,
  );
}

List<Override> fixedGroups(List<Group> groups) {
  return [
    clockProvider.overrideWithValue(FixedClock(sampleNow)),
    findGroupsViewModelProvider.overrideWith(() => FixedFindGroups(groups)),
  ];
}
