import 'package:flutter/foundation.dart';
import 'package:scapematch/core/device/install_id.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/web/document_base.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/auth_return_url.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/data/signup_confirmation.dart';

/// O que o Auth respondeu ao criar a conta da casa.
enum PartnerSignupStatus { confirmEmail, signedIn }

/// Cadastro real da casa no Supabase Auth. O teste troca esta classe.
class PartnerSignupGateway {
  const PartnerSignupGateway();

  /// [error] preenchido quando a conta não nasceu.
  Future<({PartnerSignupStatus? status, String? error})> create({
    required String name,
    required String email,
    required String password,
  }) async {
    final rejected = await rejectPassword(password);
    if (rejected != null) return (status: null, error: rejected);
    try {
      final response = await scapeSupabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: _redirect(),
        data: {
          'display_name': name,
          'device_install_id': ?await InstallId.readOrCreate(),
        },
      );
      if (response.session == null) {
        return (status: PartnerSignupStatus.confirmEmail, error: null);
      }
      await scapeSupabase.rpc(
        'accept_terms',
        params: {'p_audience': 'partner'},
      );
      return (status: PartnerSignupStatus.signedIn, error: null);
    } on Object catch (error) {
      return (
        status: null,
        error: authErrorMessage(
          error,
          fallback: 'Não foi possível criar a conta. Tente de novo.',
        ),
      );
    }
  }

  Future<String?> resend(String email) {
    return resendSignupConfirmation(
      client: scapeSupabase,
      email: email,
      emailRedirectTo: _redirect(),
    );
  }

  String? _redirect() {
    if (!kIsWeb) return null;
    final href = documentBaseHref();
    if (href == null || href.isEmpty) return null;
    return authReturnUrl(Uri.base, href);
  }
}
