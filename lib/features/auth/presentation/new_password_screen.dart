import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/password_field.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';

/// Pede a senha nova depois do link de recuperação.
///
/// [onSave] devolve a frase de erro, ou nulo quando gravou.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({
    super.key,
    required this.onSave,
    required this.onCancel,
  });

  final Future<String?> Function(String password) onSave;

  /// Sai da troca. Quem chama limpa o aviso e encerra a sessão.
  final Future<void> Function() onCancel;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(_rebuild);
    _confirm.addListener(_rebuild);
  }

  @override
  void dispose() {
    _password.removeListener(_rebuild);
    _confirm.removeListener(_rebuild);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _matches =>
      _password.text.isNotEmpty && _password.text == _confirm.text;

  String? get _mismatch =>
      _confirm.text.isNotEmpty && _confirm.text != _password.text
      ? passwordMismatchMessage
      : null;

  Future<void> _submit() async {
    if (!_matches) {
      setState(() => _error = passwordMismatchMessage);
      return;
    }
    final rule = passwordRuleError(_password.text);
    if (rule != null) {
      setState(() => _error = rule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onSave(_password.text);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    await widget.onCancel();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      desktopMaxWidth: AppScaffold.formMax,
      appBar: AppBar(title: const Text('Nova senha')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Escolha uma senha nova. Use pelo menos 8 caracteres, com letras e números.',
          ),
          const SizedBox(height: 16),
          PasswordField(
            fieldKey: AppKeys.newPassword,
            controller: _password,
            labelText: 'Nova senha',
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          PasswordField(
            fieldKey: AppKeys.confirmNewPassword,
            controller: _confirm,
            labelText: 'Confirmar senha',
            errorText: _mismatch,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_matches && !_busy) _submit();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: AppKeys.newPasswordError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: AppKeys.newPasswordSubmit,
            onPressed: _busy || !_matches ? null : _submit,
            child: const Text('Salvar senha'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: AppKeys.newPasswordCancel,
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
