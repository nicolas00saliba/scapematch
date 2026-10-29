import 'package:scapematch/features/account/domain/current_user.dart';

/// Sessão local. O Supabase Auth entra no lugar desta interface.
abstract class AuthRepository {
  CurrentUser? get signedInUser;

  /// Mensagem de erro, ou nulo quando entrou.
  Future<String?> signIn({required String email, required String password});

  /// Cria a conta de exemplo e já entra. Mensagem de erro, ou nulo.
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<void> signOut();
}
