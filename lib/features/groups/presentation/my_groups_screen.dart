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
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/invite_sheet.dart';
import 'package:scapematch/features/groups/presentation/my_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

class MyGroupsScreen extends ConsumerWidget {
  const MyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return AppScaffold(
        appBar: AppBar(title: const Text('Meus grupos')),
        body: EmptyView(
          title: GroupMessages.signInToSeeGroups,
          message: GroupMessages.signInToSeeGroupsBody,
          icon: Icons.lock_outline,
          actionKey: AppKeys.myGroupsSignIn,
          actionLabel: GroupMessages.signIn,
          onAction: () => context.push(loginLocation('/groups/mine')),
        ),
      );
    }
    final groups = ref.watch(myGroupsViewModelProvider);
    final now = ref.watch(clockProvider).now();
    final userId = session.id;

    return AppScaffold(
      appBar: AppBar(title: const Text('Meus grupos')),
      body: groups.when(
        loading: () => const LoadingView(message: 'Carregando seus grupos...'),
        error: (error, stackTrace) => ErrorView(
          message: 'Não foi possível carregar seus grupos.',
          onRetry: () => ref.invalidate(myGroupsViewModelProvider),
        ),
        data: (items) {
          final split = splitMyGroups(groups: items, userId: userId, now: now);
          return DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(key: AppKeys.myGroupsUpcoming, text: 'Próximos'),
                    Tab(key: AppKeys.myGroupsPast, text: 'Passados'),
                    Tab(key: AppKeys.myGroupsCancelled, text: 'Cancelados'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _GroupList(
                        groups: split.upcoming,
                        userId: userId,
                        emptyTitle: 'Nenhum grupo marcado',
                        emptyMessage: 'Você ainda não tem grupos marcados. Encontre um ou crie o seu.',
                      ),
                      _GroupList(
                        groups: split.past,
                        userId: userId,
                        emptyTitle: 'Nenhuma sessão passada',
                        emptyMessage: 'Quando uma sessão terminar sem ser cancelada, ela aparece aqui.',
                      ),
                      _GroupList(
                        groups: split.cancelled,
                        userId: userId,
                        emptyTitle: 'Nenhum cancelamento',
                        emptyMessage: 'Grupos excluídos e saídas aparecem aqui, com o reembolso simulado.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.userId,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Group> groups;
  final String userId;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return EmptyView(title: emptyTitle, message: emptyMessage);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: groups.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const ExampleDataBanner();
        }
        final group = groups[index - 1];
        return _MyGroupCard(
          group: group,
          member: group.participantForUser(userId),
          onTap: () => context.push('/groups/${group.id}'),
          onInvite: () => showInviteSheet(context, group),
        );
      },
    );
  }
}

class _MyGroupCard extends StatelessWidget {
  const _MyGroupCard({
    required this.group,
    required this.member,
    required this.onTap,
    required this.onInvite,
  });

  final Group group;
  final Participant? member;
  final VoidCallback onTap;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refund = member == null ? null : GroupMessages.refundLabel(member!);
    final attendance = member == null
        ? null
        : GroupMessages.attendanceLabel(member!.attendance);

    return Card(
      child: InkWell(
        key: AppKeys.groupCard(group.id),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.roomName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${group.houseName} · ${group.cityName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(formatSession(group.startsAt)),
              const SizedBox(height: 8),
              Text(
                '${formatPrice(group.priceCents)} por pessoa · ${GroupMessages.paymentLabel}',
              ),
              if (attendance != null) ...[
                const SizedBox(height: 4),
                Text(
                  attendance,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (refund != null) ...[
                const SizedBox(height: 4),
                Text(
                  refund,
                  key: AppKeys.refundStatus,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (group.isCancelled) ...[
                const SizedBox(height: 4),
                const Text(
                  'Grupo cancelado',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: AppKeys.inviteOnCard(group.id),
                  onPressed: onInvite,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Convidar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
