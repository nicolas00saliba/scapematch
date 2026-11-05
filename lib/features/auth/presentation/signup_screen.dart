import 'package:dominio/dominio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/auth/presentation/signup_success_view.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/presentation/invite_join.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/providers/repositories.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.resendCooldown = signupResendCooldown});

  /// Testes encurtam a espera. O app usa [signupResendCooldown].
  final Duration resendCooldown;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _day = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();
  String? _error;
  String? _pendingEmail;
  var _busy = false;
  var _accepted = false;
  List<City> _cities = knownCities;
  String? _cityId;
  late final TapGestureRecognizer _termsLink;
  late final TapGestureRecognizer _privacyLink;
  late final TapGestureRecognizer _refundLink;

  @override
  void initState() {
    super.initState();
    _termsLink = TapGestureRecognizer()
      ..onTap = () => context.push('/legal/termos');
    _privacyLink = TapGestureRecognizer()
      ..onTap = () => context.push('/legal/privacidade');
    _refundLink = TapGestureRecognizer()
      ..onTap = () => context.push('/legal/reembolso');
    _cityId = ref.read(selectedCityIdProvider);
    if (!scapeUsesLiveBackend) return;
    Future<void>(() async {
      final cities = await ref.read(cityRepositoryProvider).listCities();
      if (!mounted || cities.isEmpty) return;
      setState(() => _cities = cities);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _day.dispose();
    _month.dispose();
    _year.dispose();
    _termsLink.dispose();
    _privacyLink.dispose();
    _refundLink.dispose();
    super.dispose();
  }

  DateTime? _birthDate() {
    final day = int.tryParse(_day.text.trim());
    final month = int.tryParse(_month.text.trim());
    final year = int.tryParse(_year.text.trim());
    if (day == null || month == null || year == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final birthDate = _birthDate();
    if (!scapeUsesLiveBackend) {
      if (name.isEmpty || !email.contains('@') || password.length < 4) {
        setState(() {
          _error = 'Preencha nome, um e-mail e uma senha de 4 caracteres.';
        });
        return;
      }
    } else {
      if (name.isEmpty || !email.contains('@')) {
        setState(() => _error = 'Preencha nome e um e-mail válido.');
        return;
      }
      final rule = passwordRuleError(password);
      if (rule != null) {
        setState(() => _error = rule);
        return;
      }
    }
    if (scapeUsesLiveBackend && (_cityId == null || _cityId!.isEmpty)) {
      setState(() => _error = 'Escolha a cidade.');
      return;
    }
    if (birthDate == null) {
      setState(() => _error = 'Informe uma data de nascimento válida.');
      return;
    }
    if (!_accepted) {
      setState(() => _error = LegalDocuments.termsRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authSessionProvider.notifier)
        .signUp(
          name: name,
          email: email,
          password: password,
          birthDate: birthDate,
          acceptedTerms: _accepted,
          cityId: _cityId,
        );
    if (!mounted) {
      return;
    }
    if (error == signupAwaitingEmailConfirmation) {
      setState(() {
        _busy = false;
        _error = null;
        _pendingEmail = email;
      });
      return;
    }
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    final pending = await consumePendingInvite(ref);
    if (!mounted) {
      return;
    }
    final groupId = pending.groupId;
    if (groupId == null) {
      final next = GoRouterState.of(context).uri.queryParameters['next'];
      context.go(afterAuthLocation(next));
      return;
    }
    context.go('/groups/$groupId', extra: pending.notice);
  }

  Widget _termsSentence(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.35);
    final link = TextStyle(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      height: 1.35,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Li e aceito os '),
          TextSpan(text: 'termos', style: link, recognizer: _termsLink),
          const TextSpan(text: ', a '),
          TextSpan(text: 'privacidade', style: link, recognizer: _privacyLink),
          const TextSpan(text: ' e o '),
          TextSpan(text: 'reembolso', style: link, recognizer: _refundLink),
          TextSpan(text: ' (versão $legalDocumentVersion).'),
        ],
      ),
    );
  }

  void _openLogin() {
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    if (next == null || next.isEmpty) {
      context.go('/login');
      return;
    }
    context.go(loginLocation(next));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingEmail;
    if (pending != null) {
      return AppScaffold(
        desktopMaxWidth: AppScaffold.formMax,
        appBar: AppBar(leading: ScapeBackButton(), title: Text('Conta criada')),
        body: SignupSuccessView(
          email: pending,
          cooldown: widget.resendCooldown,
          onLogin: _openLogin,
          onResend: () {
            return ref
                .read(authSessionProvider.notifier)
                .resendSignupEmail(email: pending);
          },
        ),
      );
    }
    return AppScaffold(
      desktopMaxWidth: AppScaffold.formMax,
      appBar: AppBar(leading: ScapeBackButton(), title: Text('Cadastro')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ExampleDataBanner(),
            const SizedBox(height: 16),
            Text(
              scapeUsesLiveBackend
                  ? 'A conta fica no ScapeMatch. O perfil nasce com o seu nome. O cadastro só segue com o aceite.'
                  : 'O cadastro só segue com o aceite. A versão do texto e a data ficam registradas.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: AppKeys.signupName,
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('signup-city-${_cities.length}-$_cityId'),
              initialValue: _cities.any((city) => city.id == _cityId)
                  ? _cityId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Cidade',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final city in _cities)
                  DropdownMenuItem(value: city.id, child: Text(city.name)),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _cityId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: AppKeys.signupEmail,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: AppKeys.signupBirthDay,
                    controller: _day,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Dia',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: AppKeys.signupBirthMonth,
                    controller: _month,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mês',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: AppKeys.signupBirthYear,
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: AppKeys.signupPassword,
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Senha',
                helperText: scapeUsesLiveBackend
                    ? 'Pelo menos 8 caracteres, com letras e números.'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LegalDocuments.reviewBanner,
              key: AppKeys.signupTermsBanner,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  key: AppKeys.signupTerms,
                  value: _accepted,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _accepted = value ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(child: _termsSentence(context)),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
            const SizedBox(height: 16),
            FilledButton(
              key: AppKeys.signupSubmit,
              onPressed: _busy ? null : _submit,
              child: const Text('Criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}
