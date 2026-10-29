import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/sharing/group_link.dart';
import 'package:scapematch/core/sharing/invite_message.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/invite_card.dart';

/// Opções de convite: link, WhatsApp, share do sistema e o cartão visual.
Future<void> showInviteSheet(BuildContext context, Group group) {
  final message = inviteMessage(group);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Convidar',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              InviteCard(group: group),
              const SizedBox(height: 12),
              SelectableText(message, key: AppKeys.inviteMessage),
              const SizedBox(height: 12),
              FilledButton(
                key: AppKeys.shareGroup,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: groupLink(group.id)),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(GroupMessages.linkCopied)),
                    );
                  }
                },
                child: const Text('Copiar link'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: AppKeys.inviteWhatsApp,
                onPressed: () async {
                  final opened = await openExternalUrl(
                    Uri.parse(whatsAppShareUrl(message)),
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (!opened) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Não foi possível abrir o WhatsApp. Copie a mensagem.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('WhatsApp'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: AppKeys.inviteShare,
                onPressed: () async {
                  final shared = await sharePlainText(message);
                  if (!context.mounted || shared) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Este aparelho não abriu a folha de compartilhar. Copie a mensagem.',
                      ),
                    ),
                  );
                },
                child: const Text('Compartilhar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: AppKeys.inviteImage,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(GroupMessages.inviteImageLater),
                    ),
                  );
                },
                child: const Text('Compartilhar cartão'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
