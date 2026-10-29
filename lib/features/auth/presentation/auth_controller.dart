import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
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
    final error = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
    state = ref.read(authRepositoryProvider).signedInUser;
    return error;
  }

  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final error = await ref
        .read(authRepositoryProvider)
        .signUp(name: name, email: email, password: password);
    state = ref.read(authRepositoryProvider).signedInUser;
    return error;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = ref.read(authRepositoryProvider).signedInUser;
  }
}
