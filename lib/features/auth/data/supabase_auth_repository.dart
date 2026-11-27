import 'package:dominio/dominio.dart';
import 'package:flutter/foundation.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/core/device/install_id.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/auth_redirect.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:scapematch/features/auth/data/google_oauth_flow.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/data/signup_confirmation.dart';
import 'package:scapematch/features/auth/domain/auth_repository.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
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
      final fromAuth = currentUserFromAuth(user);
      final profileBirth = birth == null
          ? null
          : DateTime.parse(birth.toString());
      _profile = CurrentUser(
        id: user.id,
        displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
            ? (row['display_name'] as String).trim()
            : fromAuth.displayName,
        username: username == null || username.isEmpty ? null : username,
        birthDate: profileBirth ?? fromAuth.birthDate,
        cityId: cityIdOf(user),
        googleProfilePending:
            googleOnlyUser(user) &&
            (profileBirth == null || fromAuth.birthDate == null),
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
    String? referralCode,
    String? phone,
  }) async {
    if (!acceptedTerms) return LegalDocuments.termsRequired;
    if (!GroupRules.isAdult(birthDate: birthDate, now: now)) {
      return LegalDocuments.under18;
    }
    final rejected = await rejectPassword(password);
    if (rejected != null) return rejected;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Informe o nome.';
    final phoneDigits = _phoneDigits(phone);
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: kIsWeb ? _webRedirect() : null,
        data: {
          'display_name': trimmed,
          'birth_date': _isoDate(birthDate),
          if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
          if (referralCode != null && referralCode.trim().isNotEmpty)
            'referral_code': referralCode.trim(),
          'phone': ?phoneDigits,
          'device_install_id': ?await InstallId.readOrCreate(),
        },
      );
      if (response.session == null) {
        return signupAwaitingEmailConfirmation;
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
  Future<String?> resendSignupEmail({required String email}) {
    return resendSignupConfirmation(
      client: _client,
      email: email,
      emailRedirectTo: kIsWeb ? _webRedirect() : null,
    );
  }

  @override
  Future<String?> changePassword({required String password}) async {
    if (_client.auth.currentUser == null) {
      return passwordRecoverySessionMessage;
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
  Future<String?> signInWithGoogle() => startGoogleOAuth(_client.auth);

  @override
  Future<String?> completeGoogleProfile({
    required String name,
    required DateTime birthDate,
    required DateTime now,
    required bool acceptedTerms,
    String? cityId,
    String? referralCode,
    String? phone,
  }) async {
    if (!acceptedTerms) return LegalDocuments.termsRequired;
    if (!GroupRules.isAdult(birthDate: birthDate, now: now)) {
      return LegalDocuments.under18;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Informe o nome.';
    if (trimmed.length > 80) {
      return 'O nome pode ter no máximo 80 caracteres.';
    }
    final user = _client.auth.currentUser;
    if (user == null) return 'Entre para concluir o cadastro.';
    final phoneDigits = _phoneDigits(phone);
    if (phone != null && phone.trim().isNotEmpty && phoneDigits == null) {
      return 'Informe o telefone com DDD, só números.';
    }
    final referral = referralCode?.trim();
    final iso = _isoDate(birthDate);
    try {
      if (referral != null && referral.isNotEmpty) {
        final status = await _client.rpc(
          'claim_referral_code',
          params: {'p_code': referral},
        );
        final claim = referralClaimMessage('${status ?? 'invalid'}');
        if (claim != null) return claim;
      }
      await _client.rpc('accept_terms', params: {'p_audience': 'player'});
      await _client
          .from('profiles')
          .update({'display_name': trimmed, 'birth_date': iso})
          .eq('id', user.id);
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            'display_name': trimmed,
            'birth_date': iso,
            if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
            'phone': ?phoneDigits,
            if (referral != null && referral.isNotEmpty)
              'referral_code': referral,
            'device_install_id': ?await InstallId.readOrCreate(),
          },
        ),
      );
      try {
        await _client.rpc('apply_signup_meta');
      } on Object {
        // Telefone e aparelho são opcionais. Sem a migração, o cadastro
        // obrigatório já ficou no perfil e no aceite.
      }
      await refresh();
      return null;
    } on Object catch (error) {
      return authErrorMessage(
        error,
        fallback: 'Não foi possível concluir o cadastro. Tente de novo.',
      );
    }
  }

  @override
  String get suggestedName {
    final user = _client.auth.currentUser;
    return suggestedOAuthName(user?.userMetadata, user?.email);
  }

  @override
  String? get sessionEmail => _client.auth.currentUser?.email;

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

  static String? _webRedirect() => webAuthRedirect();
}

CurrentUser currentUserFromAuth(User user) {
  final meta = user.userMetadata ?? const <String, dynamic>{};
  final name = suggestedOAuthName(meta, user.email);
  DateTime? birth;
  final rawBirth = meta['birth_date'];
  if (rawBirth is String && rawBirth.isNotEmpty) {
    birth = DateTime.tryParse(rawBirth);
  }
  final googleOnly = googleOnlyUser(user);
  return CurrentUser(
    id: user.id,
    displayName: name.length > 80 ? name.substring(0, 80) : name,
    birthDate: birth,
    cityId: cityIdOf(user),
    googleProfilePending: googleOnly && birth == null,
  );
}

/// Só a identidade Google. E-mail junto com Google é a conta que já existia.
bool googleOnlyUser(User user) {
  final identities = user.identities;
  if (identities != null && identities.isNotEmpty) {
    return googleOnlyProviders(identities.map((identity) => identity.provider));
  }
  final provider = user.appMetadata['provider'];
  if (provider is String && provider.isNotEmpty) {
    return provider == 'google';
  }
  final providers = user.appMetadata['providers'];
  if (providers is List) {
    return googleOnlyProviders(providers.whereType<String>());
  }
  return false;
}

String? _phoneDigits(String? phone) {
  if (phone == null || phone.trim().isEmpty) return null;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^[0-9]{10,13}$').hasMatch(digits)) return null;
  return digits;
}

String? cityIdOf(User user) {
  final value = user.userMetadata?['city_id'];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}
