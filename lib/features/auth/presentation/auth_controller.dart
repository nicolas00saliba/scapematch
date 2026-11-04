import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/providers/repositories.dart';

/// Sessão atual. Nulo é visitante. O app de exemplo começa com Nícolas.
final authSessionProvider = NotifierProvider<AuthController, CurrentUser?>(
  AuthController.new,
);

class AuthController extends Notifier<CurrentUser?> {
  @override
  CurrentUser? build() => ref.watch(authRepositoryProvider).signedInUser;

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final error = await repo.signIn(email: email, password: password);
    await repo.refresh();
    state = repo.signedInUser;
    _rememberCity();
    return error;
  }

  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
    required DateTime birthDate,
    required bool acceptedTerms,
    String? cityId,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final error = await repo.signUp(
      name: name,
      email: email,
      password: password,
      birthDate: birthDate,
      now: ref.read(clockProvider).now(),
      acceptedTerms: acceptedTerms,
      cityId: cityId,
    );
    await repo.refresh();
    state = repo.signedInUser;
    _rememberCity();
    return error;
  }

  Future<String?> requestPasswordReset({required String email}) {
    return ref.read(authRepositoryProvider).requestPasswordReset(email: email);
  }

  Future<void> signOut() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.signOut();
    state = repo.signedInUser;
  }

  void _rememberCity() {
    final cityId = state?.cityId;
    if (cityId == null || cityId.isEmpty) return;
    ref.read(selectedCityIdProvider.notifier).select(cityId);
  }
}
