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
  Future<JoinResult> join(
    String groupId, {
    required String participantUserId,
    required String participantName,
  });

  Future<CreateGroupResult> create(CreateGroupRequest request);
}
