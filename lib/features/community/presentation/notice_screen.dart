import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/community/domain/community_board.dart';

class NoticeScreen extends ConsumerWidget {
  const NoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider);
    ref.watch(communityTickProvider);
    final board = ref.watch(communityBoardProvider);
    final notices = user == null
        ? const <AppNotice>[]
        : board.visibleFor(user.id);
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            'Os lembretes ficam neste aparelho. O aviso no celular chega quando houver conta de verdade.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final kind in NoticeKind.values) ...[
            SwitchListTile(
              key: AppKeys.noticePref(kind.name),
              contentPadding: EdgeInsets.zero,
              title: Text(_prefTitle(kind)),
              value: user == null || board.prefOn(user.id, kind),
              onChanged: user == null
                  ? null
                  : (value) {
                      board.setPref(user.id, kind, value);
                      ref.read(communityTickProvider.notifier).bump();
                    },
            ),
          ],
          const SizedBox(height: 12),
          if (notices.isEmpty)
            const Text('Nenhum aviso agora.')
          else
            for (final notice in notices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(notice.title),
                subtitle: Text(notice.body),
              ),
        ],
      ),
    );
  }
}

String _prefTitle(NoticeKind kind) {
  return switch (kind) {
    NoticeKind.reminder24h => 'Lembrete 24 h antes',
    NoticeKind.reminder2h => 'Lembrete 2 h antes',
    NoticeKind.paymentDeadline => 'Prazo do grupo perto',
    NoticeKind.waitlistOffer => 'Vaga na lista de espera',
    NoticeKind.groupClosed => 'Grupo que não fechou',
    NoticeKind.noShowWarning => 'Aviso de falta',
  };
}
