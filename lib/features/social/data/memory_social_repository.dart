import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/social/data/sample_players.dart';
import 'package:scapematch/features/social/data/social_repository.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/features/social/domain/social_rules.dart';

class _StoredCrew {
  _StoredCrew({
    required this.id,
    required this.name,
    required this.createdBy,
    this.photoAsset,
  });

  final String id;
  final String name;
  final String? photoAsset;
  final String createdBy;
  bool deleted = false;
}

class _StoredMember {
  _StoredMember({
    required this.crewId,
    required this.userId,
    required this.status,
  });

  final String crewId;
  final String userId;
  CrewMemberStatus status;
}

/// Amigos e turmas desta sessão. Some ao fechar o app.
///
/// O mesmo objeto é o [FriendDirectory] do repositório de grupos, para a
/// entrada em turma conferir a amizade sem uma segunda lista.
class MemorySocialRepository implements SocialRepository {
  MemorySocialRepository({required this.board, required this.clock}) {
    _seed();
  }

  final CommunityBoard board;
  final Clock clock;

  final _profiles = <String, PublicProfile>{};
  final _byUsername = <String, String>{};
  final _friendships = <Friendship>[];
  final _inviteByOwner = <String, String>{};
  final _ownerByInvite = <String, String>{};
  final _crews = <_StoredCrew>[];
  final _members = <_StoredMember>[];
  var _sequence = 0;

  @override
  bool areFriends(String a, String b) {
    if (a == b) {
      return false;
    }
    for (final row in _friendships) {
      if (row.status != FriendshipStatus.accepted || !row.involves(a)) {
        continue;
      }
      if (row.otherThan(a) == b) {
        return true;
      }
    }
    return false;
  }

  @override
  PublicProfile? profileOf(String userId) => _profiles[userId];

  @override
  Future<SocialView> viewFor(
    String userId, {
    String? displayName,
    String? username,
  }) async {
    _ensureProfile(
      userId,
      displayName: displayName ?? 'Jogador',
      username: username,
    );
    return _view(userId);
  }

  @override
  Future<SocialResult> requestByUsername({
    required String actorId,
    required String username,
  }) async {
    final handle = SocialRules.normalizeUsername(username);
    if (handle == null) {
      return const SocialFailure(
        'O usuário precisa ter de 3 a 20 letras, números ou _.',
      );
    }
    final otherId = _byUsername[handle];
    if (otherId == null) {
      return const SocialFailure('Não encontramos esse usuário.');
    }
    return _request(actorId: actorId, otherId: otherId);
  }

  @override
  Future<SocialResult> requestByInvite({
    required String actorId,
    required String code,
  }) async {
    final owner = _ownerByInvite[code.trim().toLowerCase()];
    if (owner == null) {
      return const SocialFailure('Esse convite não existe.');
    }
    return _request(actorId: actorId, otherId: owner);
  }

  @override
  Future<SocialResult> acceptFriend({
    required String actorId,
    required String friendshipId,
  }) async {
    final index = _indexOfFriendship(friendshipId);
    if (index < 0) {
      return const SocialFailure('Esse pedido não está mais aqui.');
    }
    final row = _friendships[index];
    if (row.addresseeId != actorId || row.status != FriendshipStatus.pending) {
      return const SocialFailure('Só quem recebeu o pedido pode aceitar.');
    }
    _friendships[index] = Friendship(
      id: row.id,
      requesterId: row.requesterId,
      addresseeId: row.addresseeId,
      status: FriendshipStatus.accepted,
    );
    final me = _profiles[actorId];
    _notify(
      userId: row.requesterId,
      kind: NoticeKind.friendAccepted,
      title: 'Amizade aceita',
      body: '${me?.displayName ?? 'Alguém'} aceitou seu pedido.',
      scope: row.id,
    );
    return const SocialOk('Vocês agora são amigos.');
  }

  @override
  Future<SocialResult> declineFriend({
    required String actorId,
    required String friendshipId,
  }) async {
    final index = _indexOfFriendship(friendshipId);
    if (index < 0) {
      return const SocialFailure('Esse pedido não está mais aqui.');
    }
    final row = _friendships[index];
    if (row.addresseeId != actorId || row.status != FriendshipStatus.pending) {
      return const SocialFailure('Só quem recebeu o pedido pode recusar.');
    }
    _friendships.removeAt(index);
    return const SocialOk('Pedido recusado.');
  }

  @override
  Future<SocialResult> removeFriend({
    required String actorId,
    required String otherUserId,
  }) async {
    final index = _friendships.indexWhere(
      (row) =>
          row.status == FriendshipStatus.accepted &&
          row.involves(actorId) &&
          row.otherThan(actorId) == otherUserId,
    );
    if (index < 0) {
      return const SocialFailure('Essa amizade não está na sua lista.');
    }
    _friendships.removeAt(index);
    return const SocialOk('Amizade removida.');
  }

  @override
  Future<SocialResult> blockUser({
    required String actorId,
    required String otherUserId,
  }) async {
    if (actorId == otherUserId) {
      return const SocialFailure('Você não pode bloquear a própria conta.');
    }
    if (_profiles[otherUserId] == null) {
      return const SocialFailure('Não encontramos essa pessoa.');
    }
    final index = _friendships.indexWhere(
      (row) => row.involves(actorId) && row.otherThan(actorId) == otherUserId,
    );
    if (index >= 0) {
      final row = _friendships[index];
      _friendships[index] = Friendship(
        id: row.id,
        requesterId: row.requesterId,
        addresseeId: row.addresseeId,
        status: FriendshipStatus.blocked,
        blockedBy: actorId,
      );
    } else {
      _friendships.add(
        Friendship(
          id: _next('fr'),
          requesterId: actorId,
          addresseeId: otherUserId,
          status: FriendshipStatus.blocked,
          blockedBy: actorId,
        ),
      );
    }
    board.block(actorId, otherUserId);
    return const SocialOk('Pessoa bloqueada.');
  }

  @override
  Future<SocialResult> unblockUser({
    required String actorId,
    required String otherUserId,
  }) async {
    final index = _friendships.indexWhere(
      (row) =>
          row.status == FriendshipStatus.blocked &&
          row.blockedBy == actorId &&
          row.involves(actorId) &&
          row.otherThan(actorId) == otherUserId,
    );
    if (index < 0) {
      return const SocialFailure('Esse bloqueio não é seu.');
    }
    _friendships.removeAt(index);
    board.unblock(actorId, otherUserId);
    return const SocialOk('Bloqueio removido.');
  }

  @override
  Future<SocialResult> createCrew({
    required String actorId,
    required String name,
    required List<String> friendIds,
    String? photoAsset,
  }) async {
    final crewName = SocialRules.normalizeCrewName(name);
    if (crewName == null) {
      return const SocialFailure(
        'O nome da turma precisa ter de 2 a 40 letras.',
      );
    }
    final unique = friendIds.toSet().where((id) => id != actorId).toList();
    if (unique.isEmpty) {
      return const SocialFailure('Escolha pelo menos um amigo.');
    }
    if (unique.length > 11) {
      return const SocialFailure('Uma turma cabe no máximo 12 pessoas.');
    }
    for (final id in unique) {
      if (!areFriends(actorId, id)) {
        return const SocialFailure('Só dá para chamar amigos aceitos.');
      }
    }
    final crew = _StoredCrew(
      id: _next('crew'),
      name: crewName,
      createdBy: actorId,
      photoAsset: photoAsset,
    );
    _crews.add(crew);
    _members.add(
      _StoredMember(
        crewId: crew.id,
        userId: actorId,
        status: CrewMemberStatus.accepted,
      ),
    );
    final me = _profiles[actorId];
    for (final id in unique) {
      _members.add(
        _StoredMember(
          crewId: crew.id,
          userId: id,
          status: CrewMemberStatus.invited,
        ),
      );
      _notify(
        userId: id,
        kind: NoticeKind.crewInvite,
        title: 'Convite de turma',
        body: '${me?.displayName ?? 'Alguém'} chamou você para $crewName.',
        scope: crew.id,
      );
    }
    return SocialOk(
      'Turma criada. Cada pessoa aceita o convite na própria conta.',
    );
  }

  @override
  Future<SocialResult> respondCrew({
    required String actorId,
    required String crewId,
    required bool accept,
  }) async {
    final crew = _crew(crewId);
    if (crew == null || crew.deleted) {
      return const SocialFailure('Essa turma não existe.');
    }
    final member = _member(crewId, actorId);
    if (member == null || member.status != CrewMemberStatus.invited) {
      return const SocialFailure('Não há convite seu nessa turma.');
    }
    member.status = accept ? CrewMemberStatus.accepted : CrewMemberStatus.left;
    if (accept) {
      final me = _profiles[actorId];
      _notify(
        userId: crew.createdBy,
        kind: NoticeKind.crewInvite,
        title: 'Turma',
        body: '${me?.displayName ?? 'Alguém'} entrou em ${crew.name}.',
        scope: 'joined-$crewId-$actorId',
      );
      return const SocialOk('Você entrou na turma.');
    }
    return const SocialOk('Convite recusado.');
  }

  @override
  Future<SocialResult> leaveCrew({
    required String actorId,
    required String crewId,
  }) async {
    final crew = _crew(crewId);
    if (crew == null || crew.deleted) {
      return const SocialFailure('Essa turma não existe.');
    }
    if (crew.createdBy == actorId) {
      return const SocialFailure('Quem criou a turma exclui em vez de sair.');
    }
    final member = _member(crewId, actorId);
    if (member == null || member.status != CrewMemberStatus.accepted) {
      return const SocialFailure('Você não está nessa turma.');
    }
    member.status = CrewMemberStatus.left;
    return const SocialOk('Você saiu da turma.');
  }

  @override
  Future<SocialResult> deleteCrew({
    required String actorId,
    required String crewId,
  }) async {
    final crew = _crew(crewId);
    if (crew == null || crew.deleted) {
      return const SocialFailure('Essa turma não existe.');
    }
    if (crew.createdBy != actorId) {
      return const SocialFailure('Só quem criou pode excluir a turma.');
    }
    crew.deleted = true;
    for (final member in _members) {
      if (member.crewId == crewId) {
        member.status = CrewMemberStatus.left;
      }
    }
    return const SocialOk('Turma excluída.');
  }

  @override
  List<PartyCompanion> companionsForCrew({
    required String actorId,
    required String crewId,
  }) {
    final crew = _crew(crewId);
    final mine = _member(crewId, actorId);
    if (crew == null ||
        crew.deleted ||
        mine == null ||
        mine.status != CrewMemberStatus.accepted) {
      return const [];
    }
    return [
      for (final member in _members)
        if (member.crewId == crewId &&
            member.userId != actorId &&
            member.status == CrewMemberStatus.accepted)
          PartyCompanion(
            userId: member.userId,
            displayName: _profiles[member.userId]?.displayName ?? 'Amigo',
          ),
    ];
  }

  SocialResult _request({required String actorId, required String otherId}) {
    _ensureProfile(actorId, displayName: 'Jogador');
    if (actorId == otherId) {
      return const SocialFailure('Você não pode adicionar a própria conta.');
    }
    final existing = _between(actorId, otherId);
    if (existing != null) {
      if (existing.status == FriendshipStatus.blocked) {
        return const SocialFailure('Não dá para pedir amizade.');
      }
      if (existing.status == FriendshipStatus.accepted) {
        return const SocialFailure('Vocês já são amigos.');
      }
      if (existing.addresseeId == actorId) {
        final index = _indexOfFriendship(existing.id);
        _friendships[index] = Friendship(
          id: existing.id,
          requesterId: existing.requesterId,
          addresseeId: existing.addresseeId,
          status: FriendshipStatus.accepted,
        );
        return const SocialOk(
          'Esse pedido já era seu. Vocês agora são amigos.',
        );
      }
      return const SocialFailure('O pedido já foi enviado.');
    }
    final id = _next('fr');
    _friendships.add(
      Friendship(
        id: id,
        requesterId: actorId,
        addresseeId: otherId,
        status: FriendshipStatus.pending,
      ),
    );
    final me = _profiles[actorId];
    _notify(
      userId: otherId,
      kind: NoticeKind.friendRequest,
      title: 'Pedido de amizade',
      body: '${me?.displayName ?? 'Alguém'} quer ser seu amigo.',
      scope: id,
    );
    return const SocialOk('Pedido enviado.');
  }

  SocialView _view(String userId) {
    final me = _profiles[userId]!;
    final incoming = <FriendCard>[];
    final outgoing = <FriendCard>[];
    final friends = <FriendCard>[];
    final blocked = <FriendCard>[];
    for (final row in _friendships) {
      if (!row.involves(userId)) {
        continue;
      }
      final other = _profiles[row.otherThan(userId)];
      if (other == null) {
        continue;
      }
      final card = FriendCard(
        friendshipId: row.id,
        userId: other.id,
        username: other.username,
        displayName: other.displayName,
        status: row.status,
        incoming: row.addresseeId == userId,
      );
      switch (row.status) {
        case FriendshipStatus.pending:
          if (card.incoming) {
            incoming.add(card);
          } else {
            outgoing.add(card);
          }
        case FriendshipStatus.accepted:
          friends.add(card);
        case FriendshipStatus.blocked:
          if (row.blockedBy == userId) {
            blocked.add(card);
          }
      }
    }
    friends.sort((a, b) => a.displayName.compareTo(b.displayName));
    final crews = <CrewView>[
      for (final crew in _crews)
        if (!crew.deleted && _visibleMember(crew.id, userId) != null)
          CrewView(
            id: crew.id,
            name: crew.name,
            photoAsset: crew.photoAsset,
            createdBy: crew.createdBy,
            viewerId: userId,
            myStatus: _visibleMember(crew.id, userId)!.status,
            people: [
              for (final member in _members)
                if (member.crewId == crew.id &&
                    member.status != CrewMemberStatus.left &&
                    _profiles[member.userId] != null)
                  CrewPerson(
                    userId: member.userId,
                    displayName: _profiles[member.userId]!.displayName,
                    username: _profiles[member.userId]!.username,
                    status: member.status,
                  ),
            ],
          ),
    ];
    return SocialView(
      me: me,
      inviteCode: _inviteByOwner[userId] ?? '',
      incoming: incoming,
      outgoing: outgoing,
      friends: friends,
      blocked: blocked,
      crews: crews,
    );
  }

  void _seed() {
    for (final profile in sampleProfiles) {
      _remember(profile);
    }
    void friends(String a, String b) {
      _friendships.add(
        Friendship(
          id: _next('fr'),
          requesterId: a,
          addresseeId: b,
          status: FriendshipStatus.accepted,
        ),
      );
    }

    friends(sampleLocalUserId, 'user-marina');
    friends(sampleLocalUserId, 'user-caio');
    friends(sampleLocalUserId, 'user-helena');
    friends(sampleLocalUserId, 'user-vera');
    friends(sampleLocalUserId, sampleCrewMateLuna);
    friends(sampleLocalUserId, sampleCrewMateEnzo);
    _friendships.add(
      Friendship(
        id: 'fr-lia',
        requesterId: 'user-lia',
        addresseeId: sampleLocalUserId,
        status: FriendshipStatus.pending,
      ),
    );
    _friendships.add(
      Friendship(
        id: 'fr-rafa',
        requesterId: sampleLocalUserId,
        addresseeId: 'user-rafa',
        status: FriendshipStatus.pending,
      ),
    );
    _crews.add(
      _StoredCrew(
        id: sampleCrewId,
        name: 'Sábado à noite',
        createdBy: sampleLocalUserId,
        photoAsset: 'assets/images/people/03.jpg',
      ),
    );
    for (final id in [
      sampleLocalUserId,
      sampleCrewMateLuna,
      sampleCrewMateEnzo,
    ]) {
      _members.add(
        _StoredMember(
          crewId: sampleCrewId,
          userId: id,
          status: CrewMemberStatus.accepted,
        ),
      );
    }
    _members.add(
      _StoredMember(
        crewId: sampleCrewId,
        userId: 'user-helena',
        status: CrewMemberStatus.invited,
      ),
    );
    _notify(
      userId: sampleLocalUserId,
      kind: NoticeKind.friendRequest,
      title: 'Pedido de amizade',
      body: 'Lia quer ser sua amiga.',
      scope: 'fr-lia',
    );
  }

  void _ensureProfile(
    String id, {
    required String displayName,
    String? username,
  }) {
    if (_profiles.containsKey(id)) {
      return;
    }
    final base =
        SocialRules.normalizeUsername(username ?? displayName) ?? 'jogador';
    var candidate = base;
    var suffix = 2;
    while (_byUsername.containsKey(candidate)) {
      final tail = '$suffix';
      final room = 20 - tail.length;
      final stem = base.length > room ? base.substring(0, room) : base;
      candidate = '$stem$tail';
      suffix += 1;
    }
    _remember(
      PublicProfile(
        id: id,
        displayName: displayName.trim().isEmpty
            ? 'Jogador'
            : displayName.trim(),
        username: candidate,
      ),
    );
  }

  void _remember(PublicProfile profile) {
    _profiles[profile.id] = profile;
    _byUsername[profile.username] = profile.id;
    final code = '${profile.username}-demo';
    _inviteByOwner[profile.id] = code;
    _ownerByInvite[code] = profile.id;
  }

  Friendship? _between(String a, String b) {
    for (final row in _friendships) {
      if (row.involves(a) && row.otherThan(a) == b) {
        return row;
      }
    }
    return null;
  }

  int _indexOfFriendship(String id) =>
      _friendships.indexWhere((row) => row.id == id);

  _StoredCrew? _crew(String id) {
    for (final crew in _crews) {
      if (crew.id == id) {
        return crew;
      }
    }
    return null;
  }

  _StoredMember? _member(String crewId, String userId) {
    for (final member in _members) {
      if (member.crewId == crewId && member.userId == userId) {
        return member;
      }
    }
    return null;
  }

  _StoredMember? _visibleMember(String crewId, String userId) {
    final member = _member(crewId, userId);
    if (member == null || member.status == CrewMemberStatus.left) {
      return null;
    }
    return member;
  }

  void _notify({
    required String userId,
    required NoticeKind kind,
    required String title,
    required String body,
    required String scope,
  }) {
    board.postNotice(
      userId: userId,
      kind: kind,
      title: title,
      body: body,
      at: clock.now(),
      scope: scope,
    );
  }

  String _next(String prefix) {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
