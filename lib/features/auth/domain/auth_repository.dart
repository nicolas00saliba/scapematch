import 'package:dominio/dominio.dart';
import 'package:scapematch/features/account/domain/current_user.dart';

/// Sessão local. O Supabase Auth entra no lugar desta interface.
abstract class AuthRepository {
  CurrentUser? get signedInUser;

  /// Mensagem de erro, ou nulo quando entrou.
  Future<String?> signIn({required String email, required String password});

  /// Cria a conta. Nulo quando a sessão já existe.
  /// `signupAwaitingEmailConfirmation` quando o e-mail ainda precisa
  /// ser aberto. Qualquer outra string é erro.
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

  /// Reenvia o e-mail de confirmação do cadastro. Nulo quando saiu.
  Future<String?> resendSignupEmail({required String email});

  /// Pede o e-mail de nova senha. Nulo quando o pedido foi aceito.
  Future<String?> requestPasswordReset({required String email});

  /// Troca a senha de quem está na sessão. Nulo quando a senha nova valeu.
  Future<String?> changePassword({required String password});

  /// Relê o perfil depois do login. A implementação em memória não faz nada.
  Future<void> refresh() async {}

  Future<void> signOut();

  /// Aceites desta sessão de exemplo. A conta real grava pela função accept_terms.
  List<LegalAcceptance> get acceptances;
}
