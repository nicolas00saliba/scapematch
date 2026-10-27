import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/my_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

/// View model of one group.
///
/// Mutations ask the repository, then update this screen and the lists that
/// show the same group. The name comes from [currentUserProvider].
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
        _publish(group);
        return null;
      case JoinFailure(:final reason):
        return reason;
    }
  }

  Future<ConfirmAttendanceFailureReason?> confirmAttendance() async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .confirmAttendance(groupId, userId: user.id);
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case ConfirmAttendanceSuccess(:final group):
        _publish(group);
        return null;
      case ConfirmAttendanceFailure(:final reason):
        return reason;
    }
  }

  Future<LeaveGroupResult?> leave() async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .leave(groupId, userId: user.id);
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case LeaveGroupSuccess(:final group):
        _publish(group);
        return result;
      case LeaveGroupFailure():
        return result;
    }
  }

  Future<DeleteGroupFailureReason?> deleteGroup() async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .deleteGroup(groupId, userId: user.id);
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case DeleteGroupSuccess(:final group):
        _publish(group);
        return null;
      case DeleteGroupFailure(:final reason):
        return reason;
    }
  }

  Future<RemoveMemberFailureReason?> removeMember(String memberId) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .removeMember(groupId, actorUserId: user.id, memberId: memberId);
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case RemoveMemberSuccess(:final group):
        _publish(group);
        return null;
      case RemoveMemberFailure(:final reason):
        return reason;
    }
  }

  Future<EditGroupFailureReason?> edit({
    required int totalSpots,
    required String note,
  }) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .edit(
          groupId,
          actorUserId: user.id,
          totalSpots: totalSpots,
          note: note,
        );
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case EditGroupSuccess(:final group):
        _publish(group);
        return null;
      case EditGroupFailure(:final reason):
        return reason;
    }
  }

  void _publish(Group group) {
    state = AsyncData(group);
    ref.invalidate(findGroupsViewModelProvider);
    ref.invalidate(myGroupsViewModelProvider);
  }
}

final groupDetailViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<GroupDetailViewModel, Group, String>(GroupDetailViewModel.new);
