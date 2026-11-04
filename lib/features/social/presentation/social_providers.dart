import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/providers/repositories.dart';

class SocialTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final socialTickProvider = NotifierProvider<SocialTick, int>(SocialTick.new);

/// Nulo sem sessão. A lista é só da pessoa logada.
final socialViewProvider = FutureProvider<SocialView?>((ref) async {
  ref.watch(socialTickProvider);
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return null;
  }
  return ref
      .watch(socialRepositoryProvider)
      .viewFor(
        session.id,
        displayName: session.displayName,
        username: session.username,
      );
});

/// Id da turma usada no filtro da Home. Nulo desliga o filtro.
class CrewSpotFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? crewId) => state = crewId;
}

final crewSpotFilterProvider = NotifierProvider<CrewSpotFilter, String?>(
  CrewSpotFilter.new,
);
