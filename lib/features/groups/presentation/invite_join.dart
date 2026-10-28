import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/my_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

/// Entra no grupo guardado. Limpa a intenção mesmo se a vaga sumiu.
Future<({String? groupId, String? notice})> consumePendingInvite(
  WidgetRef ref,
) async {
  final store = ref.read(pendingInviteStoreProvider);
  final groupId = store.groupId;
  if (groupId == null) {
    return (groupId: null, notice: null);
  }
  await store.clear();
  final user = ref.read(authSessionProvider);
  if (user == null) {
    return (groupId: null, notice: null);
  }
  final result = await ref
      .read(groupRepositoryProvider)
      .join(
        groupId,
        participantUserId: user.id,
        participantName: user.displayName,
      );
  ref.invalidate(findGroupsViewModelProvider);
  ref.invalidate(myGroupsViewModelProvider);
  ref.invalidate(groupDetailViewModelProvider(groupId));
  return switch (result) {
    JoinSuccess() => (groupId: groupId, notice: null),
    JoinFailure(:final reason) => (
      groupId: groupId,
      notice: switch (reason) {
        JoinFailureReason.full => GroupMessages.inviteBecameFull,
        JoinFailureReason.alreadyStarted => 'Este grupo já começou.',
        JoinFailureReason.alreadyJoined => null,
        _ => 'Não foi possível entrar neste grupo.',
      },
    ),
  };
}
