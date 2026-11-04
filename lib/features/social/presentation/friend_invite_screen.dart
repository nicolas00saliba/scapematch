import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/features/social/presentation/social_providers.dart';
import 'package:scapematch/providers/repositories.dart';

/// Abre o link ou o QR de convite e manda o pedido de amizade.
class FriendInviteScreen extends ConsumerWidget {
  const FriendInviteScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return AppScaffold(
      desktopMaxWidth: AppScaffold.readingMax,
      appBar: AppBar(
        leading: const ScapeBackButton(),
        title: const Text('Convite de amigo'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Código $code'),
          const SizedBox(height: 12),
          Text(
            'Quem recebe o pedido decide se aceita. Nenhum dado além do nome e do usuário aparece aqui.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 16),
          if (session == null)
            FilledButton(
              onPressed: () => context.push(loginLocation('/amigos/c/$code')),
              child: const Text('Entrar para pedir amizade'),
            )
          else
            FilledButton(
              key: AppKeys.redeemInvite,
              onPressed: () async {
                final result = await ref
                    .read(socialRepositoryProvider)
                    .requestByInvite(actorId: session.id, code: code);
                ref.read(socialTickProvider.notifier).bump();
                if (!context.mounted) {
                  return;
                }
                final message = switch (result) {
                  SocialOk(:final message) => message ?? 'Pedido enviado.',
                  SocialFailure(:final message) => message,
                };
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
                if (result is SocialOk) {
                  context.go('/account/friends');
                }
              },
              child: const Text('Pedir amizade'),
            ),
        ],
      ),
    );
  }
}
