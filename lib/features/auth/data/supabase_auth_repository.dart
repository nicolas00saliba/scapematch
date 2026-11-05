import 'package:dominio/dominio.dart';
import 'package:flutter/foundation.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Conta real. O perfil nasce no gatilho `handle_new_user`.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;
  CurrentUser? _profile;

  @override
  CurrentUser? get signedInUser {
    final user = _client.auth.currentUser;
    if (user == null) {
      _profile = null;
      return null;
    }
    final cached = _profile;
    if (cached != null && cached.id == user.id) return cached;
    return _profile = currentUserFromAuth(user);
  }

  @override
  Future<void> refresh() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _profile = null;
      return;
    }
    try {
      final row = await _client
          .from('profiles')
          .select('display_name, birth_date, username')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) {
        _profile = currentUserFromAuth(user);
        return;
      }
      final birth = row['birth_date'];
      final username = (row['username'] as String?)?.trim();
      _profile = CurrentUser(
        id: user.id,
        displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
            ? (row['display_name'] as String).trim()
            : currentUserFromAuth(user).displayName,
        username: username == null || username.isEmpty ? null : username,
        birthDate: birth == null
            ? currentUserFromAuth(user).birthDate
            : DateTime.parse(birth.toString()),
        cityId: cityIdOf(user),
      );
    } on Object {
      _profile = currentUserFromAuth(user);
    }
  }

  @override
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await refresh();
      return null;
    } on Object catch (error) {
      return authErrorMessage(
        error,
        fallback: 'Não foi possível entrar agora. Tente de novo.',
      );
    }
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
    if (!acceptedTerms) return LegalDocuments.termsRequired;
    if (!GroupRules.isAdult(birthDate: birthDate, now: now)) {
      return LegalDocuments.under18;
    }
    final rejected = await rejectPassword(password);
    if (rejected != null) return rejected;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Informe o nome.';
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'display_name': trimmed,
          'birth_date': _isoDate(birthDate),
          if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
        },
      );
      if (response.session == null) {
        return 'Abra o e-mail para confirmar a conta e depois entre.';
      }
      await _client.rpc('accept_terms', params: {'p_audience': 'player'});
      await refresh();
      return null;
    } on Object catch (error) {
      return authErrorMessage(
        error,
        fallback: 'Não foi possível criar a conta. Tente de novo.',
      );
    }
  }

  @override
  Future<String?> changePassword({required String password}) async {
    if (_client.auth.currentUser == null) {
      return 'Entre para trocar a senha.';
    }
    final rejected = await rejectPassword(password);
    if (rejected != null) return rejected;
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      return null;
    } on Object catch (error) {
      return authErrorMessage(
        error,
        fallback: 'Não foi possível trocar a senha. Tente de novo.',
      );
    }
  }

  @override
  Future<String?> requestPasswordReset({required String email}) async {
    final trimmed = email.trim();
    if (!trimmed.contains('@')) return 'Informe um e-mail válido.';
    try {
      await _client.auth.resetPasswordForEmail(
        trimmed,
        redirectTo: kIsWeb ? _webRedirect() : null,
      );
      return null;
    } on Object catch (error) {
      return authErrorMessage(
        error,
        fallback: 'Não foi possível enviar o e-mail. Tente de novo.',
      );
    }
  }

  @override
  List<LegalAcceptance> get acceptances => const [];

  @override
  Future<void> signOut() async {
    _profile = null;
    await _client.auth.signOut();
  }

  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String? _webRedirect() {
    final base = Uri.base;
    if (!base.hasScheme || base.host.isEmpty) return null;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: path, query: '', fragment: '').toString();
  }
}

CurrentUser currentUserFromAuth(User user) {
  final meta = user.userMetadata ?? const <String, dynamic>{};
  final fromMeta = (meta['display_name'] as String?)?.trim();
  final emailName = (user.email ?? 'jogador').split('@').first;
  final name = (fromMeta == null || fromMeta.isEmpty) ? emailName : fromMeta;
  DateTime? birth;
  final rawBirth = meta['birth_date'];
  if (rawBirth is String && rawBirth.isNotEmpty) {
    birth = DateTime.tryParse(rawBirth);
  }
  return CurrentUser(
    id: user.id,
    displayName: name.length > 80 ? name.substring(0, 80) : name,
    birthDate: birth,
    cityId: cityIdOf(user),
  );
}

String? cityIdOf(User user) {
  final value = user.userMetadata?['city_id'];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}
