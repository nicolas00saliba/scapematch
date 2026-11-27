import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/password_field.dart';

/// Pede a senha nova. [changePassword] devolve a frase de erro, ou nulo.
Future<void> showPasswordChangeDialog({
  required BuildContext context,
  required Future<String?> Function(String password) changePassword,
}) {
  final password = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (context) {
      var busy = false;
      String? error;
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Trocar senha'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Use pelo menos 8 caracteres, com letras e números. Senhas que já vazaram não entram.',
                ),
                const SizedBox(height: 12),
                PasswordField(
                  fieldKey: AppKeys.changePasswordField,
                  controller: password,
                  labelText: 'Nova senha',
                  autofillHints: const [AutofillHints.newPassword],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: AppKeys.changePasswordSubmit,
                onPressed: busy
                    ? null
                    : () async {
                        setLocal(() {
                          busy = true;
                          error = null;
                        });
                        final failure = await changePassword(password.text);
                        if (!context.mounted) return;
                        if (failure != null) {
                          setLocal(() {
                            busy = false;
                            error = failure;
                          });
                          return;
                        }
                        Navigator.pop(context);
                      },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(password.dispose);
}
