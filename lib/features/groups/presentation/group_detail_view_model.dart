import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

/// View model of one group.
///
/// [join] asks the repository to add the current user and then updates
/// this screen. The name comes from [currentUserProvider], not from a
/// literal. A full group is refused by the repository even if the button
/// was enabled by mistake. Joining does not wait for the organizer.
class GroupDetailViewModel extends AsyncNotifier<Group> {
  GroupDetailViewModel(this.groupId);

  final String groupId;

  @override
  Future<Group> build() async {
    final group = await ref.watch(groupRepositoryProvider).getById(groupId);
    if (group == null) {
      throw GroupNotFoundException(groupId);
    }
    return group;
  }

  /// Returns null when the person entered the group.
  Future<JoinFailureReason?> join() async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .join(
          groupId,
          participantUserId: user.id,
          participantName: user.displayName,
        );
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case JoinSuccess(:final group):
        state = AsyncData(group);
        ref.invalidate(findGroupsViewModelProvider);
        return null;
      case JoinFailure(:final reason):
        return reason;
    }
  }
}

final groupDetailViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<GroupDetailViewModel, Group, String>(GroupDetailViewModel.new);
