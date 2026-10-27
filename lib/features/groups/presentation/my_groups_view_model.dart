import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/providers/repositories.dart';

/// Groups the current user created or joined, including cancelled ones.
class MyGroupsViewModel extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() {
    final userId = ref.watch(currentUserProvider).id;
    return ref.watch(groupRepositoryProvider).listForUser(userId);
  }
}

final myGroupsViewModelProvider =
    AsyncNotifierProvider.autoDispose<MyGroupsViewModel, List<Group>>(
      MyGroupsViewModel.new,
    );

/// Splits [groups] into upcoming seats and the history tab.
({List<Group> upcoming, List<Group> history}) splitMyGroups({
  required List<Group> groups,
  required String userId,
  required DateTime now,
}) {
  final upcoming = <Group>[];
  final history = <Group>[];
  for (final group in groups) {
    final member = group.participantForUser(userId);
    final active = member != null && member.occupiesSeat;
    final isUpcoming = GroupRules.isUpcomingForMember(
      groupCancelled: group.isCancelled,
      memberActive: active,
      endsAt: group.endsAt,
      now: now,
    );
    if (isUpcoming) {
      upcoming.add(group);
    } else {
      history.add(group);
    }
  }
  upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  history.sort((a, b) => b.startsAt.compareTo(a.startsAt));
  return (upcoming: upcoming, history: history);
}
