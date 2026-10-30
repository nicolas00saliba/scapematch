import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/community/domain/community_board.dart';

class AccountDataScreen extends ConsumerWidget {
  const AccountDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider);
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Meus dados')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            'O que esta versão de exemplo guarda da sua conta.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text('Nome: ${user?.displayName ?? 'Sem sessão'}'),
          const SizedBox(height: 8),
          Text('Id: ${user?.id ?? '—'}'),
          const SizedBox(height: 8),
          const Text(
            'E-mail e data de nascimento ficam na conta criada no cadastro. A senha não aparece aqui.',
          ),
        ],
      ),
    );
  }
}

class AccountDeletionScreen extends ConsumerWidget {
  const AccountDeletionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            'O pedido fica registrado neste exemplo. A conta não é apagada de verdade e nada sai deste aparelho.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: AppKeys.accountDelete,
            onPressed: () {
              final user = ref.read(authSessionProvider);
              if (user != null) {
                ref.read(communityBoardProvider).deletionRequests.add(user.id);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Pedido de exclusão registrado. A conta de exemplo continua.',
                  ),
                ),
              );
            },
            child: const Text('Pedir exclusão da conta'),
          ),
        ],
      ),
    );
  }
}
