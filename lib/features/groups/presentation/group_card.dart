import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = '${group.filledSpots} de ${group.totalSpots} vagas';
    final progress = group.totalSpots == 0
        ? 0.0
        : (group.filledSpots / group.totalSpots).clamp(0, 1).toDouble();

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
            padding: const EdgeInsets.all(16),
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
                const SizedBox(height: 4),
                Text(
                  '${group.houseName} · ${group.neighborhood}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.teal),
                    const SizedBox(width: 6),
                    Expanded(child: Text(formatSession(group.startsAt))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  spots,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  GroupMessages.confirmedCount(group.confirmedCount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatPrice(group.priceCents)} por pessoa',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.tealSoft,
                    color: group.isFull ? AppColors.muted : AppColors.teal,
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
    final (label, background, foreground) = switch ((
      group.isFull,
      group.isAlmostFull,
    )) {
      (true, _) => ('Cheio', AppColors.line, AppColors.muted),
      (false, true) => (
        'Quase cheio',
        AppColors.copperSoft,
        AppColors.copperInk,
      ),
      _ => ('Aberto', AppColors.tealSoft, AppColors.teal),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
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
