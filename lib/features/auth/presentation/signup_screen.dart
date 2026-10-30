import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/groups/presentation/invite_join.dart';
import 'package:scapematch/features/legal/legal_documents.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

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
  var _busy = false;
  var _accepted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _day.dispose();
    _month.dispose();
    _year.dispose();
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
    if (name.isEmpty || !email.contains('@') || password.length < 4) {
      setState(() {
        _error = 'Preencha nome, um e-mail e uma senha de 4 caracteres.';
      });
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
        );
    if (!mounted) {
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Cadastro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          const Text('Cadastro de exemplo, só neste aparelho. Sem servidor.'),
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
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: AppKeys.signupTerms,
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: (value) => setState(() => _accepted = value ?? false),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Li e aceito os '),
                TextButton(
                  onPressed: () => context.push('/legal/termos'),
                  child: const Text('termos'),
                ),
                const Text(', a '),
                TextButton(
                  onPressed: () => context.push('/legal/privacidade'),
                  child: const Text('privacidade'),
                ),
                const Text(' e o '),
                TextButton(
                  onPressed: () => context.push('/legal/reembolso'),
                  child: const Text('reembolso'),
                ),
                const Text('.'),
              ],
            ),
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
    );
  }
}
