import 'package:scapematch/features/account/domain/current_user.dart';

/// Sessão local. O Supabase Auth entra no lugar desta interface.
abstract class AuthRepository {
  CurrentUser? get signedInUser;

  /// Mensagem de erro, ou nulo quando entrou.
  Future<String?> signIn({required String email, required String password});

  /// Cria a conta e já entra. Mensagem de erro, ou nulo.
  ///
  /// [cityId] vai no perfil via metadado do gatilho `handle_new_user`.
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
    required DateTime birthDate,
    required DateTime now,
    required bool acceptedTerms,
    String? cityId,
  });

  /// Pede o e-mail de nova senha. Nulo quando o pedido foi aceito.
  Future<String?> requestPasswordReset({required String email});

  /// Relê o perfil depois do login. A implementação em memória não faz nada.
  Future<void> refresh() async {}

  Future<void> signOut();
}
