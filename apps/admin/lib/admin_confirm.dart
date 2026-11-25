import 'package:flutter/material.dart';

/// Confirmação digitada. O botão só segue quando o texto é exatamente [word].
Future<bool> confirmTyped(
  BuildContext context, {
  required String title,
  required String body,
  required String word,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDialog(title: title, body: body, word: word),
  );
  return accepted == true;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.word,
  });

  final String title;
  final String body;
  final String word;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.body),
          const SizedBox(height: 12),
          Text('Digite ${widget.word} para confirmar.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('admin-confirm-word'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.word),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('admin-confirm-ok'),
          onPressed: () {
            if (_controller.text.trim() != widget.word) return;
            Navigator.pop(context, true);
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
