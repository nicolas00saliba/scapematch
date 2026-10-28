import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/invite_card.dart';
import 'package:scapematch/providers/repositories.dart';

/// Convite público. Dá para ler o grupo sem conta. Participar pede login.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(groupDetailViewModelProvider(groupId));
    final now = ref.watch(clockProvider).now();
    return AppScaffold(
      appBar: AppBar(title: const Text('Convite')),
      body: detail.when(
        loading: () => const LoadingView(message: 'Carregando o convite...'),
        error: (error, stackTrace) => EmptyView(
          title: 'Convite não encontrado',
          message: 'Esse link não aponta para um grupo de exemplo.',
          icon: Icons.link_off,
          actionKey: AppKeys.inviteMissingHome,
          actionLabel: 'Ir para a Home',
          onAction: () => context.go('/'),
        ),
        data: (group) => _InviteBody(group: group, now: now),
      ),
    );
  }
}

class _InviteBody extends ConsumerWidget {
  const _InviteBody({required this.group, required this.now});

  final Group group;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final started = GroupRules.hasStarted(startsAt: group.startsAt, now: now);
    final ended = GroupRules.hasEnded(endsAt: group.endsAt, now: now);
    final session = ref.watch(authSessionProvider);
    final mine = session == null ? null : group.participantForUser(session.id);
    final inGroup = mine != null && mine.occupiesSeat;
    final open = group.openSeats;
    final spots = open == 1 ? '1 vaga restante' : '$open vagas restantes';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const ExampleDataBanner(),
        const SizedBox(height: 12),
        InviteCard(group: group),
        const SizedBox(height: 16),
        Text(
          group.roomTheme,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 8),
        Text('${group.houseName} · ${group.neighborhood}'),
        Text(group.cityName),
        const SizedBox(height: 8),
        Text(formatSession(group.startsAt)),
        Text(
          formatStartsIn(
            startsAt: group.startsAt,
            endsAt: group.endsAt,
            now: now,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${group.filledSpots} de ${group.totalSpots} vagas · $spots',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(formatPrice(group.priceCents)),
        if (group.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(group.note),
        ],
        const SizedBox(height: 16),
        Text(
          'Quem vai',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final person in group.participants.where((p) => p.occupiesSeat))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(person.displayName),
          ),
        if (group.isCancelled) ...[
          const SizedBox(height: 12),
          const Text(GroupMessages.cancelledBanner),
        ],
        const SizedBox(height: 16),
        if (inGroup)
          FilledButton(
            key: AppKeys.participate,
            onPressed: () => context.go('/groups/${group.id}'),
            child: const Text('Você já está neste grupo'),
          )
        else if (group.isCancelled || ended)
          const FilledButton(
            onPressed: null,
            child: Text('Este convite não aceita mais gente'),
          )
        else if (started)
          const FilledButton(
            key: AppKeys.participate,
            onPressed: null,
            child: Text('Este grupo já começou'),
          )
        else if (group.isFull)
          const FilledButton(
            key: AppKeys.participate,
            onPressed: null,
            child: Text('Grupo cheio'),
          )
        else
          FilledButton(
            key: AppKeys.participate,
            onPressed: () => _participate(context, ref),
            child: const Text('Participar'),
          ),
      ],
    );
  }

  Future<void> _participate(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      await ref.read(pendingInviteStoreProvider).save(group.id);
      router.push('/login');
      return;
    }
    final reason = await ref
        .read(groupDetailViewModelProvider(group.id).notifier)
        .join();
    final notice = switch (reason) {
      null => null,
      JoinFailureReason.full => GroupMessages.inviteBecameFull,
      JoinFailureReason.alreadyStarted => 'Este grupo já começou.',
      JoinFailureReason.alreadyJoined => null,
      _ => 'Não foi possível entrar neste grupo.',
    };
    router.go('/groups/${group.id}', extra: notice);
  }
}
