import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/providers/repositories.dart';

/// Groups the current user created or joined, including cancelled ones.
class MyGroupsViewModel extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() {
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return Future.value(const []);
    }
    return ref.watch(groupRepositoryProvider).listForUser(session.id);
  }
}

final myGroupsViewModelProvider =
    AsyncNotifierProvider.autoDispose<MyGroupsViewModel, List<Group>>(
      MyGroupsViewModel.new,
    );

/// Splits [groups] into Próximos, Passados and Cancelados.
({List<Group> upcoming, List<Group> past, List<Group> cancelled})
splitMyGroups({
  required List<Group> groups,
  required String userId,
  required DateTime now,
}) {
  final upcoming = <Group>[];
  final past = <Group>[];
  final cancelled = <Group>[];
  for (final group in groups) {
    final member = group.participantForUser(userId);
    final active = member != null && member.occupiesSeat;
    switch (GroupRules.bucketForMember(
      groupCancelled: group.isCancelled,
      memberActive: active,
      endsAt: group.endsAt,
      now: now,
    )) {
      case GroupListBucket.upcoming:
        upcoming.add(group);
      case GroupListBucket.past:
        past.add(group);
      case GroupListBucket.cancelled:
        cancelled.add(group);
    }
  }
  upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  past.sort((a, b) => b.startsAt.compareTo(a.startsAt));
  cancelled.sort((a, b) => b.startsAt.compareTo(a.startsAt));
  return (upcoming: upcoming, past: past, cancelled: cancelled);
}
