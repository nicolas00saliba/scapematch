import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AdminPhase { loading, signedOut, denied, enroll, verify, ready }

/// Nome do fator TOTP no app autenticador.
const adminTotpLabel = 'EscapeMatch Admin';

const adminMfaVerificationFailed =
    'Código inválido. Confira se o relógio do celular está em hora automática e use o código da conta $adminTotpLabel.';

const adminMfaFactorNameConflict =
    'Já existe um autenticador com o nome $adminTotpLabel. Saia e entre de novo; se a conta já estiver no app, use o código dela.';

const adminMfaGenericGateError = 'Não foi possível confirmar o autenticador.';

const adminMfaGenericCodeError = 'Código não confere. Tente de novo.';

const adminMfaEnrollMissing = 'Não foi possível cadastrar o autenticador.';

class AdminSession {
  const AdminSession({
    required this.phase,
    this.name,
    this.email,
    this.error,
    this.factorId,
    this.challengeId,
    this.qrCode,
    this.secret,
    this.busy = false,
  });

  final AdminPhase phase;
  final String? name;
  final String? email;
  final String? error;
  final String? factorId;
  final String? challengeId;
  final String? qrCode;
  final String? secret;
  final bool busy;
}

class AdminSessionController extends Notifier<AdminSession> {
  var _gating = false;

  @override
  AdminSession build() {
    if (!scapeUsesLiveBackend) {
      return const AdminSession(phase: AdminPhase.signedOut);
    }
    final auth = scapeSupabase.auth;
    final sub = auth.onAuthStateChange.listen((event) {
      if (event.session?.user == null) {
        state = const AdminSession(phase: AdminPhase.signedOut);
        return;
      }
      final waitingForCode =
          state.phase == AdminPhase.enroll || state.phase == AdminPhase.verify;
      if (waitingForCode &&
          event.event != AuthChangeEvent.mfaChallengeVerified) {
        return;
      }
      _gate();
    });
    ref.onDispose(sub.cancel);
    if (auth.currentUser == null) {
      return const AdminSession(phase: AdminPhase.signedOut);
    }
    Future<void>.microtask(_gate);
    return const AdminSession(phase: AdminPhase.loading);
  }

  Future<void> signIn(String email, String password) async {
    state = const AdminSession(phase: AdminPhase.signedOut, busy: true);
    if (!scapeUsesLiveBackend) {
      state = const AdminSession(
        phase: AdminPhase.signedOut,
        error: 'Não entrou. Confira o e-mail e a senha.',
      );
      return;
    }
    try {
      await scapeSupabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on Object {
      state = const AdminSession(
        phase: AdminPhase.signedOut,
        error: 'Não entrou. Confira o e-mail e a senha.',
      );
    }
  }

  Future<void> confirmCode(String raw) async {
    if (!scapeUsesLiveBackend) return;
    final code = raw.trim();
    final current = state;
    final factorId = current.factorId;
    if (factorId == null) return;
    if (code.length != 6) {
      state = AdminSession(
        phase: current.phase,
        email: current.email,
        factorId: factorId,
        challengeId: current.challengeId,
        qrCode: current.qrCode,
        secret: current.secret,
        error: 'O código tem 6 dígitos.',
      );
      return;
    }
    state = AdminSession(
      phase: current.phase,
      email: current.email,
      factorId: factorId,
      challengeId: current.challengeId,
      qrCode: current.qrCode,
      secret: current.secret,
      busy: true,
    );
    try {
      final challengeId = current.challengeId;
      if (challengeId == null) {
        await scapeSupabase.auth.mfa.challengeAndVerify(
          factorId: factorId,
          code: code,
        );
      } else {
        await scapeSupabase.auth.mfa.verify(
          factorId: factorId,
          challengeId: challengeId,
          code: code,
        );
      }
    } on Object catch (error) {
      final replacement = await _replacementChallenge(
        factorId: factorId,
        previous: current.challengeId,
      );
      state = sessionAfterFailedMfaCode(
        current: current,
        error: error,
        replacementChallengeId: replacement,
      );
    }
  }

  Future<void> signOut() async {
    if (scapeUsesLiveBackend) {
      await scapeSupabase.auth.signOut();
    }
    state = const AdminSession(phase: AdminPhase.signedOut);
  }

  Future<void> _gate() async {
    if (_gating || !scapeUsesLiveBackend) return;
    _gating = true;
    String? email;
    try {
      final auth = scapeSupabase.auth;
      if (auth.currentUser == null) {
        state = const AdminSession(phase: AdminPhase.signedOut);
        return;
      }
      email = auth.currentUser?.email;
      final level = auth.mfa.getAuthenticatorAssuranceLevel();
      if (level.currentLevel == AuthenticatorAssuranceLevels.aal2) {
        await _loadWho();
        return;
      }
      state = await resolveAdminMfaGate(
        email: email,
        listFactors: auth.mfa.listFactors,
        unenroll: (factorId) async {
          await auth.mfa.unenroll(factorId);
        },
        enroll: () => auth.mfa.enroll(
          factorType: FactorType.totp,
          issuer: adminTotpLabel,
          friendlyName: adminTotpLabel,
        ),
        challenge: (factorId) => auth.mfa.challenge(factorId: factorId),
      );
    } on Object catch (error) {
      state = sessionAfterFailedMfaGate(error: error, email: email);
    } finally {
      _gating = false;
    }
  }

  Future<void> _loadWho() async {
    try {
      final who = await ref.read(adminApiProvider).whoami();
      state = AdminSession(
        phase: AdminPhase.ready,
        name: who.name,
        email: who.email,
      );
    } on Object {
      state = const AdminSession(
        phase: AdminPhase.denied,
        error: 'Esta conta não administra o EscapeMatch.',
      );
    }
  }

  /// Desafio novo depois de um verify recusado. Se a troca falhar, o anterior
  /// continua e a pessoa tenta de novo na mesma tela.
  Future<String?> _replacementChallenge({
    required String factorId,
    required String? previous,
  }) async {
    if (previous == null) return null;
    try {
      final challenge = await scapeSupabase.auth.mfa.challenge(
        factorId: factorId,
      );
      return challenge.id;
    } on AuthException catch (error) {
      logAdminMfaCode(error.code);
      return null;
    } on Object {
      return null;
    }
  }
}

final adminSessionProvider =
    NotifierProvider<AdminSessionController, AdminSession>(
      AdminSessionController.new,
    );

/// Só o código. A mensagem do Supabase pode carregar segredo do TOTP.
void logAdminMfaCode(String? code) {
  debugPrint('admin mfa: ${code ?? 'sem código'}');
}

String messageForAdminMfa(Object error, {required bool verifyingCode}) {
  final fallback = verifyingCode
      ? adminMfaGenericCodeError
      : adminMfaGenericGateError;
  if (error is! AuthException) return fallback;
  logAdminMfaCode(error.code);
  return switch (error.code) {
    'mfa_verification_failed' => adminMfaVerificationFailed,
    'mfa_factor_name_conflict' => adminMfaFactorNameConflict,
    _ => fallback,
  };
}

/// Mantém a mesma tela. No verify, [replacementChallengeId] vale para a
/// próxima tentativa; nulo conserva o desafio atual.
AdminSession sessionAfterFailedMfaCode({
  required AdminSession current,
  required Object error,
  String? replacementChallengeId,
}) {
  return AdminSession(
    phase: current.phase,
    email: current.email,
    factorId: current.factorId,
    challengeId: replacementChallengeId ?? current.challengeId,
    qrCode: current.qrCode,
    secret: current.secret,
    error: messageForAdminMfa(error, verifyingCode: true),
  );
}

AdminSession sessionAfterFailedMfaGate({required Object error, String? email}) {
  return AdminSession(
    phase: AdminPhase.signedOut,
    email: email,
    error: messageForAdminMfa(error, verifyingCode: false),
  );
}

bool _verifiedTotp(Factor factor) {
  return factor.factorType == FactorType.totp &&
      factor.status == FactorStatus.verified;
}

bool _unverifiedTotp(Factor factor) {
  return factor.factorType == FactorType.totp &&
      factor.status == FactorStatus.unverified;
}

/// Abre o cadastro ou o verify.
///
/// O `listFactors` do gotrue 2.27 só põe fator verified em `totp`. O segredo
/// e o QR não voltam depois do enroll, então um TOTP unverified (código
/// errado no primeiro cadastro) é removido antes de cadastrar de novo.
/// Sem isso o enroll repete o nome e o Supabase responde
/// `mfa_factor_name_conflict`.
Future<AdminSession> resolveAdminMfaGate({
  required String? email,
  required Future<AuthMFAListFactorsResponse> Function() listFactors,
  required Future<void> Function(String factorId) unenroll,
  required Future<AuthMFAEnrollResponse> Function() enroll,
  required Future<AuthMFAChallengeResponse> Function(String factorId) challenge,
}) async {
  final factors = await listFactors();
  final verified = <Factor>[
    for (final factor in factors.totp)
      if (_verifiedTotp(factor)) factor,
  ];
  if (verified.isEmpty) {
    for (final factor in factors.all) {
      if (_verifiedTotp(factor)) verified.add(factor);
    }
  }
  if (verified.isEmpty) {
    for (final factor in factors.all) {
      if (_unverifiedTotp(factor)) await unenroll(factor.id);
    }
    final enrolled = await enroll();
    final totp = enrolled.totp;
    if (totp == null) {
      return AdminSession(
        phase: AdminPhase.signedOut,
        email: email,
        error: adminMfaEnrollMissing,
      );
    }
    return AdminSession(
      phase: AdminPhase.enroll,
      email: email,
      factorId: enrolled.id,
      qrCode: totp.qrCode,
      secret: totp.secret,
    );
  }
  final factor = verified.first;
  final challenged = await challenge(factor.id);
  return AdminSession(
    phase: AdminPhase.verify,
    email: email,
    factorId: factor.id,
    challengeId: challenged.id,
  );
}
