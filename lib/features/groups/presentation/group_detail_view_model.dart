import 'package:dominio/dominio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/my_groups_view_model.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';
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

  /// [savedCardId] é o id interno de um cartão já tokenizado. Um cartão novo
  /// passa por [payWithNewCard], que chama `tokenize-card` antes da cobrança.
  Future<PayShareResult> payShare(
    PaymentMethodKind kind, {
    String? savedCardId,
    int points = 0,
  }) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .payShare(
          groupId,
          userId: user.id,
          kind: kind,
          savedCardId: savedCardId,
          points: points,
        );
    if (ref.mounted && result is PayShareSuccess) {
      _publish(result.group);
    }
    return result;
  }

  /// Tokeniza o cartão e cobra a parte com o id devolvido.
  Future<PayShareResult> payWithNewCard(CardDraft card) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .payWithNewCard(groupId, userId: user.id, card: card);
    if (ref.mounted && result is PayShareSuccess) {
      _publish(result.group);
    }
    return result;
  }

  /// Nulo quando a turma inteira sentou. A falha traz o motivo e, se houver,
  /// quem impediu a entrada. Nenhuma cadeira muda quando falha.
  Future<JoinFailure?> joinParty(List<PartyCompanion> companions) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .joinParty(
          groupId,
          leaderUserId: user.id,
          leaderName: user.displayName,
          companions: companions,
        );
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case JoinSuccess(:final group):
        _publish(group);
        return null;
      case JoinFailure failure:
        return failure;
    }
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

  Future<CloseGroupFailureReason?> closeWithFewer() async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .closeWithFewer(groupId, userId: user.id);
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case CloseGroupSuccess(:final group):
        _publish(group);
        return null;
      case CloseGroupFailure(:final reason):
        return reason;
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
    int? minimumSpots,
  }) async {
    final user = ref.read(currentUserProvider);
    final result = await ref
        .read(groupRepositoryProvider)
        .edit(
          groupId,
          actorUserId: user.id,
          totalSpots: totalSpots,
          note: note,
          minimumSpots: minimumSpots,
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

  /// Atualiza o detalhe e as duas listas. Entrar, sair, cancelar, excluir,
  /// confirmar presença, remover participante e editar passam por aqui.
  /// Meus grupos fica montado no shell, então a invalidação não pode ser
  /// só da busca.
  void _publish(Group group) {
    state = AsyncData(group);
    ref.invalidate(findGroupsViewModelProvider);
    ref.invalidate(myGroupsViewModelProvider);
  }
}

final groupDetailViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<GroupDetailViewModel, Group, String>(GroupDetailViewModel.new);
