import 'package:dominio/dominio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:scapematch/features/auth/presentation/signup_success_view.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_signup_gateway.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Conta real da casa. O aceite chama `accept_terms('partner')`.
class PartnerSignupScreen extends ConsumerStatefulWidget {
  const PartnerSignupScreen({
    super.key,
    this.gateway = const PartnerSignupGateway(),
    this.resendCooldown = signupResendCooldown,
  });

  /// Teste injeta um gateway sem rede. O app usa o Auth de verdade.
  final PartnerSignupGateway gateway;

  /// Testes encurtam a espera. O app usa [signupResendCooldown].
  final Duration resendCooldown;

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
  String? _pendingEmail;
  var _accepted = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _open(PartnerLegal.termsTitle, PartnerLegal.termsBody);
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
    if (name.length < 2 || !email.contains('@')) {
      setState(() => _error = 'Preencha nome e um e-mail válido.');
      return;
    }
    final rule = passwordRuleError(_password.text);
    if (rule != null) {
      setState(() => _error = rule);
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
    final outcome = await widget.gateway.create(
      name: name,
      email: email,
      password: _password.text,
    );
    if (!mounted) return;
    if (outcome.error != null) {
      setState(() {
        _busy = false;
        _error = outcome.error;
      });
      return;
    }
    if (outcome.status == PartnerSignupStatus.confirmEmail) {
      setState(() {
        _busy = false;
        _error = null;
        _pendingEmail = email;
      });
      return;
    }
    try {
      final account = await loadPartnerAccount();
      if (!mounted) return;
      if (account != null) {
        ref.read(partnerSessionProvider.notifier).adopt(account);
      }
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível abrir a conta. Tente entrar.';
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

  void _openLogin() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingEmail;
    if (pending != null) {
      return AppScaffold(
        desktopMaxWidth: 480,
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Conta criada'),
        ),
        body: SignupSuccessView(
          email: pending,
          cooldown: widget.resendCooldown,
          onLogin: _openLogin,
          onResend: () => widget.gateway.resend(pending),
        ),
      );
    }
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
            key: PartnerKeys.partnerSignupPassword,
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'Senha',
              helperText: 'Pelo menos 8 caracteres, com letras e números.',
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
