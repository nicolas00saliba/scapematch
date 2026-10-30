import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
    this.onInvite,
  });

  final Group group;
  final VoidCallback onTap;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spots = '${group.filledSpots} de ${group.totalSpots} vagas';

    return Semantics(
      button: true,
      identifier: 'group-card-${group.id}',
      label:
          '${group.roomName}, ${group.houseName}, ${formatSession(group.startsAt)}, $spots',
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          key: AppKeys.groupCard(group.id),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        group.roomName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(group: group),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${group.houseName} · ${group.neighborhood}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(formatSession(group.startsAt))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spots,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (onInvite != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: AppKeys.inviteOnCard(group.id),
                      onPressed: onInvite,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.secondary,
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
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground, border) = switch ((
      group.isFull,
      group.isAlmostFull,
    )) {
      (true, _) => (
        'Cheio',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        scheme.outline,
      ),
      (false, true) => (
        'Quase cheio',
        scheme.tertiary,
        scheme.onTertiary,
        scheme.onTertiary,
      ),
      _ => (
        'Aberto',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
