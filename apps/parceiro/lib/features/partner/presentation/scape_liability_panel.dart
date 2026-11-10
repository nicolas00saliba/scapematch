import 'package:flutter/material.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// O passivo e as revisões saíram daqui. As funções exigem aal2, e a sessão
/// da casa é aal1. O console do EscapeMatch já cobre as duas tarefas.
class AdminConsoleNotice extends StatelessWidget {
  const AdminConsoleNotice({super.key});

  static final console = Uri.parse('https://admin.escapematch.com.br/');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.scapeLiability,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Passivo e indicações',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'O passivo de pontos e as revisões de indicação ficam no console do EscapeMatch.',
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: PartnerKeys.adminConsole,
            onPressed: () => openExternalUrl(console),
            child: const Text('Abrir admin.escapematch.com.br'),
          ),
        ),
      ],
    );
  }
}
