import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AdminPhase { loading, signedOut, denied, enroll, verify, ready }

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
    state = const AdminSession(phase: AdminPhase.loading);
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
    } on Object {
      state = AdminSession(
        phase: current.phase,
        email: current.email,
        factorId: factorId,
        challengeId: current.challengeId,
        qrCode: current.qrCode,
        secret: current.secret,
        error: 'Código não confere. Tente de novo.',
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
    try {
      final auth = scapeSupabase.auth;
      if (auth.currentUser == null) {
        state = const AdminSession(phase: AdminPhase.signedOut);
        return;
      }
      final level = auth.mfa.getAuthenticatorAssuranceLevel();
      if (level.currentLevel == AuthenticatorAssuranceLevels.aal2) {
        await _loadWho();
        return;
      }
      final factors = await auth.mfa.listFactors();
      final email = auth.currentUser?.email;
      if (factors.totp.isEmpty) {
        final enrolled = await auth.mfa.enroll(
          factorType: FactorType.totp,
          issuer: 'EscapeMatch Admin',
          friendlyName: 'EscapeMatch Admin',
        );
        final totp = enrolled.totp;
        if (totp == null) {
          state = AdminSession(
            phase: AdminPhase.signedOut,
            email: email,
            error: 'Não foi possível cadastrar o autenticador.',
          );
          return;
        }
        state = AdminSession(
          phase: AdminPhase.enroll,
          email: email,
          factorId: enrolled.id,
          qrCode: totp.qrCode,
          secret: totp.secret,
        );
        return;
      }
      final factor = factors.totp.first;
      final challenge = await auth.mfa.challenge(factorId: factor.id);
      state = AdminSession(
        phase: AdminPhase.verify,
        email: email,
        factorId: factor.id,
        challengeId: challenge.id,
      );
    } on Object {
      state = const AdminSession(
        phase: AdminPhase.signedOut,
        error: 'Não foi possível confirmar o autenticador.',
      );
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
}

final adminSessionProvider =
    NotifierProvider<AdminSessionController, AdminSession>(
      AdminSessionController.new,
    );
