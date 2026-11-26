import 'package:dominio/dominio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/presentation/municipality_picker.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/presentation/invite_join.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch/providers/repositories.dart';

/// Cadastro que o Google não traz: nome, nascimento, termos e o que for
/// opcional no cadastro por e-mail. Sem isto a conta não segue.
class CompleteSignupScreen extends ConsumerStatefulWidget {
  const CompleteSignupScreen({super.key});

  @override
  ConsumerState<CompleteSignupScreen> createState() =>
      _CompleteSignupScreenState();
}

class _CompleteSignupScreenState extends ConsumerState<CompleteSignupScreen> {
  final _name = TextEditingController();
  final _referral = TextEditingController();
  final _phone = TextEditingController();
  final _day = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();
  String? _error;
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
    final repo = ref.read(authRepositoryProvider);
    _name.text = repo.suggestedName;
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
    _referral.dispose();
    _phone.dispose();
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
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final birthDate = _birthDate();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome.');
      return;
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
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isNotEmpty &&
        !RegExp(r'^[0-9]{10,13}$').hasMatch(phoneDigits)) {
      setState(() => _error = 'Informe o telefone com DDD, só números.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authSessionProvider.notifier)
        .completeGoogleProfile(
          name: name,
          birthDate: birthDate,
          acceptedTerms: _accepted,
          cityId: _cityId,
          referralCode: _referral.text,
          phone: phoneDigits,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    final pending = await consumePendingInvite(ref);
    if (!mounted) return;
    final groupId = pending.groupId;
    if (groupId == null) {
      final next = GoRouterState.of(context).uri.queryParameters['next'];
      context.go(afterAuthLocation(next));
      return;
    }
    context.go('/groups/$groupId', extra: pending.notice);
  }

  Future<void> _signOut() async {
    await ref.read(authSessionProvider.notifier).signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.read(authRepositoryProvider).sessionEmail;
    final theme = Theme.of(context);
    return AppScaffold(
      desktopMaxWidth: AppScaffold.formMax,
      appBar: AppBar(
        title: const Text('Completar cadastro'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _signOut,
            child: const Text('Sair'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'O Google entrou. Falta o que o cadastro por e-mail pede: nome, data de nascimento e o aceite. O CPF continua só na hora de pagar.',
            ),
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                email,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
            SearchableCityFormField(
              fieldKey: ValueKey('complete-city-${_cities.length}-$_cityId'),
              cities: _cities,
              cityId: _cityId,
              labelText: 'Cidade',
              enabled: !_busy,
              onChanged: (value) => setState(() => _cityId = value),
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
              key: AppKeys.signupPhone,
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone (opcional)',
                helperText:
                    'DDD e número. Serve para a indicação não se repetir.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: AppKeys.signupReferral,
              controller: _referral,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Código de indicação (opcional)',
                helperText: referralCodeHint(ref.watch(rewardRulesProvider)),
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LegalDocuments.reviewBanner,
              key: AppKeys.signupTermsBanner,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
              key: AppKeys.completeSignup,
              onPressed: _busy ? null : _submit,
              child: const Text('Concluir cadastro'),
            ),
          ],
        ),
      ),
    );
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
}
