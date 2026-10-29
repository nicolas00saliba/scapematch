import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';

/// Contas só na memória. A senha não sai deste objeto e não vai para o disco.
///
/// Sem [signedIn], a sessão começa vazia. O app de exemplo passa o usuário
/// Nícolas para a Home continuar aberta como hoje.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({CurrentUser? signedIn = sampleCurrentUser})
    : _user = signedIn {
    _accounts['nicolas@exemplo.invalid'] = (
      user: sampleCurrentUser,
      password: 'senha-exemplo',
    );
  }

  CurrentUser? _user;
  var _nextId = 1;
  final _accounts = <String, ({CurrentUser user, String password})>{};

  @override
  CurrentUser? get signedInUser => _user;

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
  }) async {
    final key = _normalize(email);
    if (_accounts.containsKey(key)) {
      return 'Esse e-mail já está neste exemplo. Entre com ele.';
    }
    final user = CurrentUser(
      id: 'user-signup-$_nextId',
      displayName: name.trim(),
    );
    _nextId += 1;
    _accounts[key] = (user: user, password: password);
    _user = user;
    return null;
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  static String _normalize(String email) => email.trim().toLowerCase();
}
