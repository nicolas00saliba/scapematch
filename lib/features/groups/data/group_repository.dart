import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';

/// Reads and changes groups.
///
/// The screens depend on this interface, not on the fake lists. A Supabase
/// implementation can replace the fake repository later and the pages stay.
abstract class GroupRepository {
  Future<List<Group>> listByCity(String cityId, {bool almostFullOnly = false});

  Future<Group?> getById(String id);

  /// Adds the person immediately. There is no organizer approval step.
  /// See docs/DECISOES.md. A future Supabase implementation must do the
  /// seat check and the insert in one database transaction.
  ///
  /// [markAsLocalUser] is the session flag the sample UI still reads.
  /// Tests that seat a second person pass false.
  /// Entra na fila quando o grupo está cheio. Nulo quando a pessoa foi anotada.
  Future<String?> joinWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  });

  /// Aceita a oferta da fila, se ainda estiver no prazo.
  Future<JoinResult> acceptWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  });

  Future<JoinResult> join(
    String groupId, {
    required String participantUserId,
    required String participantName,
    bool markAsLocalUser = true,
  });

  Future<CreateGroupResult> create(CreateGroupRequest request);

  /// Groups this account created or joined, including ones they left and
  /// ones the organizer cancelled. The find-a-group list does not use this.
  Future<List<Group>> listForUser(String userId);

  Future<ConfirmAttendanceResult> confirmAttendance(
    String groupId, {
    required String userId,
  });

  /// The creator cannot leave. They delete the group instead.
  Future<LeaveGroupResult> leave(String groupId, {required String userId});

  /// Cancels the event for everyone and refunds every active seat in full.
  Future<DeleteGroupResult> deleteGroup(
    String groupId, {
    required String userId,
  });

  /// Organizer removes one other person. That seat is refunded in full.
  Future<RemoveMemberResult> removeMember(
    String groupId, {
    required String actorUserId,
    required String memberId,
  });

  Future<EditGroupResult> edit(
    String groupId, {
    required String actorUserId,
    required int totalSpots,
    required String note,
  });
}
