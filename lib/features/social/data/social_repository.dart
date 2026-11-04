import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/social/domain/social_models.dart';

/// O que o grupo em memória precisa saber para sentar uma turma inteira.
///
/// A versão Supabase não consulta isso no cliente: a função
/// `join_group_with_party` confere a amizade dentro do banco.
abstract class FriendDirectory {
  bool areFriends(String a, String b);

  PublicProfile? profileOf(String userId);
}

/// Amigos, turmas e convites.
///
/// A tela depende desta interface. [MemorySocialRepository] atende a demo.
/// [SupabaseSocialRepository] chama as mesmas funções do SQL, com
/// `auth.uid()` no servidor. [actorId] só vale na memória: no banco ele
/// é ignorado para ninguém agir em nome de outra conta.
abstract class SocialRepository implements FriendDirectory {
  Future<SocialView> viewFor(
    String userId, {
    String? displayName,
    String? username,
  });

  Future<SocialResult> requestByUsername({
    required String actorId,
    required String username,
  });

  Future<SocialResult> requestByInvite({
    required String actorId,
    required String code,
  });

  Future<SocialResult> acceptFriend({
    required String actorId,
    required String friendshipId,
  });

  Future<SocialResult> declineFriend({
    required String actorId,
    required String friendshipId,
  });

  Future<SocialResult> removeFriend({
    required String actorId,
    required String otherUserId,
  });

  Future<SocialResult> blockUser({
    required String actorId,
    required String otherUserId,
  });

  Future<SocialResult> unblockUser({
    required String actorId,
    required String otherUserId,
  });

  Future<SocialResult> createCrew({
    required String actorId,
    required String name,
    required List<String> friendIds,
    String? photoAsset,
  });

  Future<SocialResult> respondCrew({
    required String actorId,
    required String crewId,
    required bool accept,
  });

  Future<SocialResult> leaveCrew({
    required String actorId,
    required String crewId,
  });

  Future<SocialResult> deleteCrew({
    required String actorId,
    required String crewId,
  });

  /// Membros aceitos, sem quem está criando ou entrando.
  List<PartyCompanion> companionsForCrew({
    required String actorId,
    required String crewId,
  });
}
