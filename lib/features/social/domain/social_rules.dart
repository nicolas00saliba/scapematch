import 'package:scapematch/features/groups/domain/group.dart';

/// Regras de amigos e turmas que não dependem de Flutter nem do banco.
abstract final class SocialRules {
  static final usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Aceita `Ana`, `@ana` e ` ana `. Devolve nulo quando o formato não serve.
  static String? normalizeUsername(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('@')) {
      value = value.substring(1);
    }
    if (!usernamePattern.hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String? normalizeCrewName(String raw) {
    final value = raw.trim();
    if (value.length < 2 || value.length > 40) {
      return null;
    }
    return value;
  }

  /// A turma inteira precisa caber. Uma vaga a menos já recusa o grupo.
  static bool groupFitsCrew({required int openSeats, required int crewSeats}) {
    if (crewSeats < 2) {
      return false;
    }
    return openSeats >= crewSeats;
  }

  static bool groupHasFriend(Group group, Set<String> friendIds) {
    if (friendIds.isEmpty) {
      return false;
    }
    for (final person in group.participants) {
      final id = person.userId;
      if (person.occupiesSeat && id != null && friendIds.contains(id)) {
        return true;
      }
    }
    return false;
  }

  /// Link que o QR mostra. A rota do app é `/amigos/c/:code`.
  static String inviteLink(String code) =>
      'https://scapematch.app/amigos/c/$code';
}
