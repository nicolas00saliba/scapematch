/// Cartão público de uma pessoa. Sem data de nascimento, e-mail ou pagamento.
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    required this.username,
  });

  final String id;
  final String displayName;

  /// Sem o @. Minúsculo, único.
  final String username;

  String get handle => '@$username';
}

enum FriendshipStatus { pending, accepted, blocked }

class Friendship {
  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    this.blockedBy,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;
  final String? blockedBy;

  bool involves(String userId) =>
      requesterId == userId || addresseeId == userId;

  String otherThan(String userId) =>
      requesterId == userId ? addresseeId : requesterId;
}

class FriendCard {
  const FriendCard({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.status,
    required this.incoming,
  });

  final String friendshipId;
  final String userId;
  final String username;
  final String displayName;
  final FriendshipStatus status;

  /// Verdadeiro quando o pedido chegou para a pessoa que está olhando.
  final bool incoming;
}

enum CrewMemberStatus { invited, accepted, left }

class CrewPerson {
  const CrewPerson({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.status,
  });

  final String userId;
  final String displayName;
  final String username;
  final CrewMemberStatus status;
}

class CrewView {
  const CrewView({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.viewerId,
    required this.myStatus,
    required this.people,
    this.photoAsset,
  });

  final String id;
  final String name;
  final String? photoAsset;
  final String createdBy;
  final String viewerId;
  final CrewMemberStatus myStatus;
  final List<CrewPerson> people;

  bool get iAmCreator => createdBy == viewerId;

  int get acceptedCount => people
      .where((person) => person.status == CrewMemberStatus.accepted)
      .length;

  /// Quem já aceitou, sem quem está olhando. É quem ocupa vaga junto.
  List<CrewPerson> companionsOf(String userId) {
    return [
      for (final person in people)
        if (person.userId != userId &&
            person.status == CrewMemberStatus.accepted)
          person,
    ];
  }
}

/// Vista da conta para a tela de amigos. Só os vínculos de quem está logado.
class SocialView {
  const SocialView({
    required this.me,
    required this.inviteCode,
    required this.incoming,
    required this.outgoing,
    required this.friends,
    required this.blocked,
    required this.crews,
  });

  final PublicProfile me;
  final String inviteCode;
  final List<FriendCard> incoming;
  final List<FriendCard> outgoing;
  final List<FriendCard> friends;
  final List<FriendCard> blocked;
  final List<CrewView> crews;

  Set<String> get friendIds => {for (final friend in friends) friend.userId};

  /// Turmas em que todo mundo que entra junto já aceitou. Mínimo de duas pessoas.
  List<CrewView> get readyCrews => [
    for (final crew in crews)
      if (crew.myStatus == CrewMemberStatus.accepted && crew.acceptedCount >= 2)
        crew,
  ];

  static const signedOut = SocialView(
    me: PublicProfile(id: '', displayName: '', username: ''),
    inviteCode: '',
    incoming: [],
    outgoing: [],
    friends: [],
    blocked: [],
    crews: [],
  );
}

sealed class SocialResult {
  const SocialResult();
}

final class SocialOk extends SocialResult {
  const SocialOk([this.message]);

  final String? message;
}

final class SocialFailure extends SocialResult {
  const SocialFailure(this.message);

  final String message;
}
