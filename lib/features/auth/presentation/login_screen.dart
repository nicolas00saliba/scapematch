import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/groups/presentation/invite_join.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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
        .read(authSessionProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
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
    await _enterPendingGroup();
  }

  Future<void> _enterPendingGroup() async {
    final pending = await consumePendingInvite(ref);
    if (!mounted) {
      return;
    }
    final groupId = pending.groupId;
    if (groupId == null) {
      context.go('/');
      return;
    }
    final notice = pending.notice;
    context.go('/groups/$groupId', extra: notice);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          const Text('Conta de exemplo. Nada disso vai para um servidor.'),
          const SizedBox(height: 16),
          TextField(
            key: AppKeys.loginEmail,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: AppKeys.loginPassword,
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          const SizedBox(height: 16),
          FilledButton(
            key: AppKeys.loginSubmit,
            onPressed: _busy ? null : _submit,
            child: const Text('Entrar'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: AppKeys.goToSignup,
            onPressed: _busy ? null : () => context.push('/cadastro'),
            child: const Text('Fazer cadastro'),
          ),
        ],
      ),
    );
  }
}
