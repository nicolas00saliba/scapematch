import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  var _joining = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupDetailViewModelProvider(widget.groupId));
    return AppScaffold(
      appBar: AppBar(title: const Text('Grupo')),
      body: detail.when(
        loading: () => const LoadingView(message: 'Carregando grupo...'),
        error: (error, stackTrace) => ErrorView(
          message: 'Não foi possível carregar este grupo.',
          onRetry: () =>
              ref.invalidate(groupDetailViewModelProvider(widget.groupId)),
        ),
        data: (group) => _content(group),
      ),
      bottomBar: detail.maybeWhen(
        data: (group) => _joinBar(group),
        orElse: () => null,
      ),
    );
  }

  Widget _content(Group group) {
    final theme = Theme.of(context);
    final progress = group.totalSpots == 0
        ? 0.0
        : (group.filledSpots / group.totalSpots).clamp(0, 1).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const ExampleDataBanner(),
        const SizedBox(height: 16),
        Text(
          group.roomName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${group.houseName} · ${group.neighborhood}',
          style: theme.textTheme.titleMedium?.copyWith(color: AppColors.muted),
        ),
        Text(
          group.cityName,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        _InfoPanel(
          icon: Icons.schedule,
          title: formatSession(group.startsAt),
          subtitle:
              '${group.durationMinutes} min · ${group.difficulty.labelPt}',
        ),
        const SizedBox(height: 12),
        Text(group.roomTheme, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text(
          'O grupo quer ${group.totalSpots} pessoas. A sala comporta até ${group.roomCapacity}.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 12),
        Text(
          '${group.filledSpots} de ${group.totalSpots} vagas',
          key: AppKeys.spotSummary,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.tealSoft,
            color: group.isFull ? AppColors.muted : AppColors.teal,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Quem já está',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final person in group.participants)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppColors.tealSoft,
              foregroundColor: AppColors.teal,
              child: Text(_initial(person.displayName)),
            ),
            title: Text(person.displayName),
            subtitle: Text(person.isCreator ? 'Criou o grupo' : 'No grupo'),
          ),
      ],
    );
  }

  Widget _joinBar(Group group) {
    if (group.joinedByMe) {
      return Container(
        key: AppKeys.joinButton,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppColors.teal),
            SizedBox(width: 8),
            Text(
              'Você está neste grupo',
              style: TextStyle(
                color: AppColors.teal,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    final full = group.isFull;
    return Semantics(
      button: true,
      enabled: !full && !_joining,
      identifier: 'join-button',
      label: full ? 'Grupo cheio' : 'Entrar no grupo',
      child: FilledButton(
        key: AppKeys.joinButton,
        onPressed: full || _joining ? null : _join,
        child: _joining
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(full ? 'Grupo cheio' : 'Entrar no grupo'),
      ),
    );
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .join();
      if (!mounted) {
        return;
      }
      final message = switch (reason) {
        null => 'Você entrou no grupo.',
        JoinFailureReason.full => 'Esse grupo já está cheio.',
        JoinFailureReason.alreadyJoined => 'Você já está neste grupo.',
        JoinFailureReason.notFound => 'Não encontramos esse grupo.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível entrar no grupo.')),
      );
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
