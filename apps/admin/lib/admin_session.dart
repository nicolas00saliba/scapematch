import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';

enum AdminPhase { loading, signedOut, denied, ready }

class AdminSession {
  const AdminSession({
    required this.phase,
    this.name,
    this.email,
    this.error,
  });

  final AdminPhase phase;
  final String? name;
  final String? email;
  final String? error;
}

class AdminSessionController extends Notifier<AdminSession> {
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
      _loadWho();
    });
    ref.onDispose(sub.cancel);
    if (auth.currentUser == null) {
      return const AdminSession(phase: AdminPhase.signedOut);
    }
    Future<void>.microtask(_loadWho);
    return const AdminSession(phase: AdminPhase.loading);
  }

  Future<void> signIn(String email, String password) async {
    state = const AdminSession(phase: AdminPhase.loading);
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

  Future<void> signOut() async {
    if (scapeUsesLiveBackend) {
      await scapeSupabase.auth.signOut();
    }
    state = const AdminSession(phase: AdminPhase.signedOut);
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
        error: 'Esta conta não administra o ScapeMatch.',
      );
    }
  }
}

final adminSessionProvider =
    NotifierProvider<AdminSessionController, AdminSession>(
      AdminSessionController.new,
    );
