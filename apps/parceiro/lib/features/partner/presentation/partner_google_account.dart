import 'package:dominio/dominio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/device/install_id.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:scapematch/features/auth/data/google_oauth_flow.dart';
import 'package:scapematch/features/auth/data/supabase_auth_repository.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abre o Google na casa. A frase é o erro; nulo quando o fluxo saiu.
Future<String?> partnerSignInWithGoogle() async {
  if (!scapeUsesLiveBackend) return googleExampleMessage;
  return startGoogleOAuth(scapeSupabase.auth);
}

/// Nome e aceite da conta da casa. A casa em si continua no cadastro do espaço.
Future<String?> finishPartnerGoogleAccount({
  required String name,
  required bool acceptedTerms,
}) async {
  if (!acceptedTerms) return PartnerLegal.termsRequired;
  final trimmed = name.trim();
  if (trimmed.length < 2) return 'Informe o nome.';
  if (trimmed.length > 80) {
    return 'O nome pode ter no máximo 80 caracteres.';
  }
  final user = scapeSupabase.auth.currentUser;
  if (user == null) return 'Entre para concluir o cadastro.';
  try {
    await scapeSupabase.rpc(
      'accept_terms',
      params: {'p_audience': 'partner'},
    );
    await scapeSupabase
        .from('profiles')
        .update({'display_name': trimmed})
        .eq('id', user.id);
    await scapeSupabase.auth.updateUser(
      UserAttributes(
        data: {
          'display_name': trimmed,
          'device_install_id': ?await InstallId.readOrCreate(),
        },
      ),
    );
    try {
      await scapeSupabase.rpc('apply_signup_meta');
    } on Object {
      // Aparelho é opcional e depende da migração.
    }
    return null;
  } on Object catch (error) {
    return authErrorMessage(
      error,
      fallback: 'Não foi possível concluir o cadastro. Tente de novo.',
    );
  }
}

/// Aceite da conta, sem casa. Quem já criou a conta por e-mail tem esta linha.
Future<bool> partnerHasAccountTerms() async {
  final user = scapeSupabase.auth.currentUser;
  if (user == null) return false;
  final rows = await scapeSupabase
      .from('terms_acceptances')
      .select('document_code, venue_id')
      .eq('user_id', user.id)
      .eq('audience', 'partner');
  for (final row in rows) {
    if (row['document_code'] == 'partner_terms' && row['venue_id'] == null) {
      return true;
    }
  }
  return false;
}

/// Segura a casa nova do Google até o aceite da conta. Depois segue o
/// cadastro do espaço, que já pede documento e termos da casa.
class PartnerGoogleAccountGate extends ConsumerStatefulWidget {
  const PartnerGoogleAccountGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PartnerGoogleAccountGate> createState() =>
      _PartnerGoogleAccountGateState();
}

class _PartnerGoogleAccountGateState
    extends ConsumerState<PartnerGoogleAccountGate> {
  var _ready = false;
  var _needsTerms = false;

  @override
  void initState() {
    super.initState();
    if (!scapeUsesLiveBackend) {
      _ready = true;
      return;
    }
    final user = scapeSupabase.auth.currentUser;
    if (user == null || !googleOnlyUser(user)) {
      _ready = true;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final accepted = await partnerHasAccountTerms();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _needsTerms = !accepted;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _needsTerms = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_needsTerms) return widget.child;
    return PartnerGoogleFinishScreen(
      onDone: () => setState(() => _needsTerms = false),
    );
  }
}

class PartnerGoogleFinishScreen extends ConsumerStatefulWidget {
  const PartnerGoogleFinishScreen({
    super.key,
    this.onSubmit,
    this.onDone,
    this.initialName = '',
  });

  final Future<String?> Function({
    required String name,
    required bool acceptedTerms,
  })?
  onSubmit;

  final VoidCallback? onDone;
  final String initialName;

  @override
  ConsumerState<PartnerGoogleFinishScreen> createState() =>
      _PartnerGoogleFinishScreenState();
}

class _PartnerGoogleFinishScreenState
    extends ConsumerState<PartnerGoogleFinishScreen> {
  late final TextEditingController _name;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;
  late final TapGestureRecognizer _refundTap;
  var _accepted = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialName.trim();
    if (seeded.isNotEmpty) {
      _name = TextEditingController(text: seeded);
    } else if (scapeUsesLiveBackend) {
      final user = scapeSupabase.auth.currentUser;
      _name = TextEditingController(
        text: suggestedOAuthName(user?.userMetadata, user?.email),
      );
    } else {
      _name = TextEditingController();
    }
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _open(
        PartnerLegal.termsTitle,
        PartnerLegal.bodyFor(ref.read(rewardRulesProvider)),
      );
    _privacyTap = TapGestureRecognizer()
      ..onTap = () =>
          _open(LegalDocuments.privacyTitle, LegalDocuments.privacyBody);
    _refundTap = TapGestureRecognizer()
      ..onTap = () =>
          _open(LegalDocuments.refundTitle, LegalDocuments.refundBody);
  }

  @override
  void dispose() {
    _name.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _refundTap.dispose();
    super.dispose();
  }

  void _open(String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PartnerLegalScreen(title: title, body: body),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final submit = widget.onSubmit ?? finishPartnerGoogleAccount;
    final error = await submit(name: _name.text, acceptedTerms: _accepted);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.35);
    return AppScaffold(
      desktopMaxWidth: 480,
      appBar: AppBar(
        title: const Text('Completar cadastro'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(partnerSessionProvider.notifier).signOut(),
            child: const Text(PartnerMessages.signOut),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Text(
            'O Google entrou. Falta o nome e o aceite da conta da casa. O cadastro do espaço, com documento e termos da casa, vem em seguida.',
            style: body,
          ),
          const SizedBox(height: 16),
          TextField(
            key: PartnerKeys.partnerGoogleName,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: PartnerKeys.partnerGoogleTerms,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            value: _accepted,
            onChanged: _busy
                ? null
                : (value) => setState(() => _accepted = value ?? false),
            title: Text.rich(
              TextSpan(
                style: body,
                children: [
                  const TextSpan(text: 'Li e aceito os '),
                  TextSpan(
                    text: 'termos',
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: _termsTap,
                  ),
                  const TextSpan(text: ', a '),
                  TextSpan(
                    text: 'privacidade',
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: _privacyTap,
                  ),
                  const TextSpan(text: ' e o '),
                  TextSpan(
                    text: 'reembolso',
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: _refundTap,
                  ),
                  TextSpan(text: ' (versão $legalDocumentVersion).'),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: PartnerKeys.partnerGoogleSubmit,
            onPressed: _busy ? null : _submit,
            child: const Text('Concluir cadastro'),
          ),
        ],
      ),
    );
  }
}
