import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_signup_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_terms_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_signup_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

class PartnerLoginScreen extends ConsumerStatefulWidget {
  const PartnerLoginScreen({super.key});

  @override
  ConsumerState<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends ConsumerState<PartnerLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(partnerSessionProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppScaffold(
      desktopMaxWidth: 480,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
        children: [
          const Center(child: PartnerLockup()),
          const SizedBox(height: 20),
          Text(
            'EscapeMatch Parceiro',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            PartnerMessages.loginTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            scapeUsesLiveBackend
                ? PartnerMessages.loginBodyLive
                : PartnerMessages.loginBody,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          if (kAllowSampleLogin) const _PartnerDemoHints(),
          const SizedBox(height: 20),
          TextField(
            key: PartnerKeys.partnerEmail,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.partnerPassword,
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: PartnerKeys.partnerLoginError,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: PartnerKeys.partnerSubmit,
            onPressed: _busy ? null : _submit,
            child: const Text('Entrar'),
          ),
          if (scapeUsesLiveBackend) ...[
            const SizedBox(height: 8),
            TextButton(
              key: PartnerKeys.partnerSignUp,
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PartnerSignupScreen(),
                        ),
                      );
                    },
              child: const Text(PartnerMessages.signUp),
            ),
          ],
          if (kAllowSampleLogin) const _PartnerDemoActions(),
        ],
      ),
    );
  }
}

/// Textos e atalhos da casa de exemplo. O release real não referencia esta classe.
class _PartnerDemoHints extends StatelessWidget {
  const _PartnerDemoHints();

  @override
  Widget build(BuildContext context) {
    if (scapeUsesLiveBackend) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          partnerDemoEmailHint(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          partnerDemoQuickLabel(),
          key: PartnerKeys.partnerQuickDemo,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PartnerDemoActions extends ConsumerWidget {
  const _PartnerDemoActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (scapeUsesLiveBackend) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        TextButton(
          key: PartnerKeys.partnerSignup,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const PartnerVenueSignupScreen(),
              ),
            );
          },
          child: const Text(PartnerMessages.signupVenue),
        ),
        TextButton(
          key: PartnerKeys.partnerTermsDemo,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const PartnerTermsScreen(),
              ),
            );
          },
          child: const Text(PartnerMessages.signupTerms),
        ),
        TextButton(
          key: PartnerKeys.partnerAdminDemo,
          onPressed: () {
            ref
                .read(partnerSessionProvider.notifier)
                .signIn(
                  email: partnerAdminAccount.email,
                  password: partnerDemoPassword,
                );
          },
          child: const Text(PartnerMessages.adminQueue),
        ),
      ],
    );
  }
}
