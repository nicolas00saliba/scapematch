import 'package:dominio/dominio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Conta real da casa. O aceite chama `accept_terms('partner')`.
class PartnerSignupScreen extends ConsumerStatefulWidget {
  const PartnerSignupScreen({super.key});

  @override
  ConsumerState<PartnerSignupScreen> createState() =>
      _PartnerSignupScreenState();
}

class _PartnerSignupScreenState extends ConsumerState<PartnerSignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;
  late final TapGestureRecognizer _refundTap;
  String? _error;
  var _accepted = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _open(
      PartnerLegal.termsTitle,
      PartnerLegal.termsBody,
    );
    _privacyTap = TapGestureRecognizer()..onTap = () => _open(
      LegalDocuments.privacyTitle,
      LegalDocuments.privacyBody,
    );
    _refundTap = TapGestureRecognizer()..onTap = () => _open(
      LegalDocuments.refundTitle,
      LegalDocuments.refundBody,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _refundTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.length < 2 || !email.contains('@') || _password.text.length < 6) {
      setState(() {
        _error = 'Preencha nome, e-mail e uma senha de 6 caracteres.';
      });
      return;
    }
    if (!_accepted) {
      setState(() => _error = PartnerLegal.termsRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await scapeSupabase.auth.signUp(
        email: email,
        password: _password.text,
        data: {'display_name': name},
      );
      if (response.session == null) {
        setState(() {
          _busy = false;
          _error = 'Abra o e-mail para confirmar a conta e depois entre.';
        });
        return;
      }
      await scapeSupabase.rpc('accept_terms', params: {'p_audience': 'partner'});
      final account = await loadPartnerAccount();
      if (!mounted) return;
      if (account != null) {
        ref.read(partnerSessionProvider.notifier).adopt(account);
      }
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = authErrorMessage(
          error,
          fallback: 'Não foi possível criar a conta. Tente de novo.',
        );
      });
    }
  }

  void _open(String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PartnerLegalScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.35);
    return AppScaffold(
      desktopMaxWidth: 480,
      appBar: AppBar(title: const Text(PartnerMessages.signUp)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          TextField(
            key: PartnerKeys.partnerEmail,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: PartnerKeys.partnerSignupTerms,
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
            key: PartnerKeys.partnerSubmit,
            onPressed: _busy ? null : _submit,
            child: const Text('Criar conta'),
          ),
        ],
      ),
    );
  }
}
