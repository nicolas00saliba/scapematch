import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
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

  Future<void> _forgot() async {
    final email = TextEditingController(text: _email.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Nova senha'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enviamos um link se este e-mail tiver conta.'),
                  const SizedBox(height: 12),
                  TextField(
                    key: AppKeys.resetEmail,
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  key: AppKeys.resetSubmit,
                  onPressed: busy
                      ? null
                      : () async {
                          setLocal(() {
                            busy = true;
                            error = null;
                          });
                          final failure = await ref
                              .read(authSessionProvider.notifier)
                              .requestPasswordReset(email: email.text);
                          if (!context.mounted) return;
                          if (failure != null) {
                            setLocal(() {
                              busy = false;
                              error = failure;
                            });
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );
    email.dispose();
    if (sent == true && mounted) {
      setState(() {
        _error = scapeUsesLiveBackend
            ? 'Se o e-mail tiver conta, o link já foi enviado.'
            : 'Neste exemplo o link não é enviado.';
      });
    }
  }

  Future<void> _enterPendingGroup() async {
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
    final notice = pending.notice;
    context.go('/groups/$groupId', extra: notice);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      desktopMaxWidth: AppScaffold.formMax,
      appBar: AppBar(leading: ScapeBackButton(), title: Text('Entrar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            scapeUsesLiveBackend
                ? 'Entre com o e-mail e a senha da sua conta.'
                : 'Conta de exemplo. Nada disso vai para um servidor.',
          ),
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
            key: AppKeys.forgotPassword,
            onPressed: _busy ? null : _forgot,
            child: const Text('Esqueci a senha'),
          ),
          TextButton(
            key: AppKeys.goToSignup,
            onPressed: _busy
                ? null
                : () {
                    final next = GoRouterState.of(context)
                        .uri
                        .queryParameters['next'];
                    final location = next == null
                        ? '/cadastro'
                        : '/cadastro?next=${Uri.encodeQueryComponent(next)}';
                    context.push(location);
                  },
            child: const Text('Fazer cadastro'),
          ),
        ],
      ),
    );
  }
}
