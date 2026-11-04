import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/social/data/social_repository.dart';
import 'package:scapematch/features/social/domain/social_models.dart';

/// Chamada `rpc` do cliente Supabase. O app de exemplo não liga uma.
typedef SocialRpc = Future<dynamic> Function(
  String function,
  Map<String, dynamic> args,
);

/// Troca da memória pelo banco. O [actorId] do contrato é ignorado:
/// cada função lê `auth.uid()` e recusa anon.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._rpc);

  final SocialRpc _rpc;
  SocialView? _cached;

  @override
  bool areFriends(String a, String b) {
    throw UnsupportedError(
      'No Supabase a amizade é conferida dentro de join_group_with_party.',
    );
  }

  @override
  PublicProfile? profileOf(String userId) => null;

  @override
  Future<SocialView> viewFor(
    String userId, {
    String? displayName,
    String? username,
  }) async {
    final friends = await _rows('list_my_friends');
    final crews = await _rows('list_my_crews');
    final code = await _rpc('my_friend_invite', const {});
    final view = _view(
      userId: userId,
      displayName: displayName,
      username: username,
      inviteCode: '$code',
      friendRows: friends,
      crewRows: crews,
    );
    _cached = view;
    return view;
  }

  @override
  Future<SocialResult> requestByUsername({
    required String actorId,
    required String username,
  }) {
    return _ok('request_friend_by_username', {'p_username': username});
  }

  @override
  Future<SocialResult> requestByInvite({
    required String actorId,
    required String code,
  }) {
    return _ok('request_friend_by_invite', {'p_code': code});
  }

  @override
  Future<SocialResult> acceptFriend({
    required String actorId,
    required String friendshipId,
  }) {
    return _ok('respond_friendship', {
      'p_friendship_id': friendshipId,
      'p_accept': true,
    });
  }

  @override
  Future<SocialResult> declineFriend({
    required String actorId,
    required String friendshipId,
  }) {
    return _ok('respond_friendship', {
      'p_friendship_id': friendshipId,
      'p_accept': false,
    });
  }

  @override
  Future<SocialResult> removeFriend({
    required String actorId,
    required String otherUserId,
  }) {
    return _ok('remove_friend', {'p_other': otherUserId});
  }

  @override
  Future<SocialResult> blockUser({
    required String actorId,
    required String otherUserId,
  }) {
    return _ok('block_user', {'p_other': otherUserId});
  }

  @override
  Future<SocialResult> unblockUser({
    required String actorId,
    required String otherUserId,
  }) {
    return _ok('unblock_user', {'p_other': otherUserId});
  }

  @override
  Future<SocialResult> createCrew({
    required String actorId,
    required String name,
    required List<String> friendIds,
    String? photoAsset,
  }) {
    return _ok('create_crew', {
      'p_name': name,
      'p_photo': photoAsset ?? '',
      'p_friend_ids': friendIds,
    });
  }

  @override
  Future<SocialResult> respondCrew({
    required String actorId,
    required String crewId,
    required bool accept,
  }) {
    return _ok('respond_crew', {'p_crew_id': crewId, 'p_accept': accept});
  }

  @override
  Future<SocialResult> leaveCrew({
    required String actorId,
    required String crewId,
  }) {
    return _ok('leave_crew', {'p_crew_id': crewId});
  }

  @override
  Future<SocialResult> deleteCrew({
    required String actorId,
    required String crewId,
  }) {
    return _ok('delete_crew', {'p_crew_id': crewId});
  }

  @override
  List<PartyCompanion> companionsForCrew({
    required String actorId,
    required String crewId,
  }) {
    final view = _cached;
    if (view == null) return const [];
    for (final crew in view.crews) {
      if (crew.id != crewId) continue;
      return [
        for (final person in crew.companionsOf(actorId))
          PartyCompanion(
            userId: person.userId,
            displayName: person.displayName,
          ),
      ];
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _rows(
    String function, [
    Map<String, dynamic> args = const {},
  ]) async {
    final raw = await _rpc(function, args);
    if (raw is! List) {
      return const [];
    }
    return [
      for (final row in raw)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  Future<SocialResult> _ok(String function, Map<String, dynamic> args) async {
    try {
      await _rpc(function, args);
      return const SocialOk();
    } catch (error) {
      return SocialFailure('$error');
    }
  }

  SocialView _view({
    required String userId,
    required String? displayName,
    required String? username,
    required String inviteCode,
    required List<Map<String, dynamic>> friendRows,
    required List<Map<String, dynamic>> crewRows,
  }) {
    final incoming = <FriendCard>[];
    final outgoing = <FriendCard>[];
    final friends = <FriendCard>[];
    final blocked = <FriendCard>[];
    for (final row in friendRows) {
      final card = FriendCard(
        friendshipId: '${row['friendship_id']}',
        userId: '${row['user_id']}',
        username: '${row['username'] ?? ''}',
        displayName: '${row['display_name'] ?? ''}',
        status: switch (row['status']) {
          'accepted' => FriendshipStatus.accepted,
          'blocked' => FriendshipStatus.blocked,
          _ => FriendshipStatus.pending,
        },
        incoming: row['incoming'] == true,
      );
      switch (card.status) {
        case FriendshipStatus.pending:
          if (card.incoming) {
            incoming.add(card);
          } else {
            outgoing.add(card);
          }
        case FriendshipStatus.accepted:
          friends.add(card);
        case FriendshipStatus.blocked:
          blocked.add(card);
      }
    }
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in crewRows) {
      grouped.putIfAbsent('${row['crew_id']}', () => []).add(row);
    }
    final crews = [
      for (final rows in grouped.values)
        CrewView(
          id: '${rows.first['crew_id']}',
          name: '${rows.first['crew_name']}',
          photoAsset: rows.first['photo_path'] as String?,
          createdBy: '${rows.first['created_by']}',
          viewerId: userId,
          myStatus: _memberStatus(rows.first['my_status']),
          people: [
            for (final row in rows)
              CrewPerson(
                userId: '${row['member_id']}',
                displayName: '${row['member_name'] ?? ''}',
                username: '${row['member_username'] ?? ''}',
                status: _memberStatus(row['member_status']),
              ),
          ],
        ),
    ];
    return SocialView(
      me: PublicProfile(
        id: userId,
        displayName: displayName ?? '',
        username: username ?? '',
      ),
      inviteCode: inviteCode,
      incoming: incoming,
      outgoing: outgoing,
      friends: friends,
      blocked: blocked,
      crews: crews,
    );
  }

  CrewMemberStatus _memberStatus(Object? raw) {
    return switch (raw) {
      'accepted' => CrewMemberStatus.accepted,
      'left' => CrewMemberStatus.left,
      _ => CrewMemberStatus.invited,
    };
  }
}

/// Entrada em grupo no banco. Não está ligada no app de exemplo.
class SupabasePartyGateway {
  const SupabasePartyGateway(this._rpc);

  final SocialRpc _rpc;

  Future<void> joinWithParty({
    required String groupId,
    required List<String> companionIds,
  }) {
    return _rpc('join_group_with_party', {
      'p_group_id': groupId,
      'p_companion_ids': companionIds,
    });
  }

  Future<void> createWithParty({
    required String sessionId,
    required int openSpots,
    required String note,
    required List<String> companionIds,
  }) {
    return _rpc('create_group_with_party', {
      'p_session_id': sessionId,
      'p_open_spots': openSpots,
      'p_note': note,
      'p_companion_ids': companionIds,
    });
  }
}
