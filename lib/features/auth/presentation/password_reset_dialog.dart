import 'package:flutter/material.dart';

/// Pede o e-mail do link de senha nova.
///
/// Devolve verdadeiro quando o pedido foi aceito. O campo vive neste
/// estado para o controller só sumir depois que o diálogo fecha.
Future<bool> showPasswordResetDialog({
  required BuildContext context,
  required String initialEmail,
  required Future<String?> Function(String email) requestReset,
  required Key emailKey,
  required Key submitKey,
  String intro = 'Enviamos um link se este e-mail tiver conta.',
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (context) {
      return _PasswordResetDialog(
        initialEmail: initialEmail,
        requestReset: requestReset,
        emailKey: emailKey,
        submitKey: submitKey,
        intro: intro,
      );
    },
  );
  return sent == true;
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({
    required this.initialEmail,
    required this.requestReset,
    required this.emailKey,
    required this.submitKey,
    required this.intro,
  });

  final String initialEmail;
  final Future<String?> Function(String email) requestReset;
  final Key emailKey;
  final Key submitKey;
  final String intro;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  late final TextEditingController _email;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.requestReset(_email.text);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova senha'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.intro),
          const SizedBox(height: 12),
          TextField(
            key: widget.emailKey,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: widget.submitKey,
          onPressed: _busy ? null : _send,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
