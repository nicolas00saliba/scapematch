import 'package:dominio/dominio.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/legal/legal_documents.dart';

/// Contas só na memória. A senha não sai deste objeto e não vai para o disco.
///
/// Sem [signedIn], a sessão começa vazia. O app de exemplo passa o usuário
/// Nícolas para a Home continuar aberta como hoje.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    CurrentUser? signedIn = sampleCurrentUser,
    this.awaitEmailConfirmation = false,
  }) : _user = signedIn {
    _accounts['nicolas@exemplo.invalid'] = (
      user: sampleCurrentUser,
      password: 'senha-exemplo',
    );
  }

  CurrentUser? _user;
  var _nextId = 1;
  final _accounts = <String, ({CurrentUser user, String password})>{};
  final List<LegalAcceptance> _acceptances = [];

  /// Cadastro real: a conta fica à espera do e-mail e a sessão não abre.
  final bool awaitEmailConfirmation;

  /// E-mails para os quais a tela pediu outro envio.
  final List<String> resentSignupEmails = [];

  /// Quando preenchido, [resendSignupEmail] devolve esta frase.
  String? resendSignupError;

  @override
  CurrentUser? get signedInUser => _user;

  @override
  List<LegalAcceptance> get acceptances => List.unmodifiable(_acceptances);

  @override
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final account = _accounts[_normalize(email)];
    if (account == null || account.password != password) {
      return 'E-mail ou senha não conferem neste exemplo.';
    }
    _user = account.user;
    return null;
  }

  @override
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
    required DateTime birthDate,
    required DateTime now,
    required bool acceptedTerms,
    String? cityId,
  }) async {
    if (!acceptedTerms) {
      return LegalDocuments.termsRequired;
    }
    if (!GroupRules.isAdult(birthDate: birthDate, now: now)) {
      return LegalDocuments.under18;
    }
    final key = _normalize(email);
    if (_accounts.containsKey(key)) {
      return 'Esse e-mail já está neste exemplo. Entre com ele.';
    }
    final user = CurrentUser(
      id: 'user-signup-$_nextId',
      displayName: name.trim(),
      birthDate: birthDate,
      cityId: cityId,
    );
    _nextId += 1;
    _accounts[key] = (user: user, password: password);
    if (awaitEmailConfirmation) {
      return signupAwaitingEmailConfirmation;
    }
    _user = user;
    final acceptedAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    for (final code in playerAcceptanceCodes) {
      _acceptances.add(
        LegalAcceptance(
          userId: user.id,
          audience: 'player',
          documentCode: code,
          documentVersion: legalDocumentVersion,
          acceptedAt: acceptedAt,
        ),
      );
    }
    return null;
  }

  @override
  Future<String?> resendSignupEmail({required String email}) async {
    final trimmed = _normalize(email);
    if (!trimmed.contains('@')) return 'Informe um e-mail válido.';
    resentSignupEmails.add(trimmed);
    return resendSignupError;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<String?> requestPasswordReset({required String email}) async {
    if (!email.contains('@')) return 'Informe um e-mail válido.';
    return 'Neste exemplo o link não é enviado.';
  }

  @override
  Future<String?> changePassword({required String password}) async {
    final user = _user;
    if (user == null) return 'Entre para trocar a senha.';
    for (final entry in _accounts.entries) {
      if (entry.value.user.id != user.id) continue;
      _accounts[entry.key] = (user: entry.value.user, password: password);
      return null;
    }
    return 'Entre para trocar a senha.';
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  static String _normalize(String email) => email.trim().toLowerCase();
}
