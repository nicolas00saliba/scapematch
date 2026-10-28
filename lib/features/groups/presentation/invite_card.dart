import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/features/groups/domain/group.dart';

/// Cartão visual do convite. Ainda não vira arquivo para mandar.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = group.openSeats;
    final spots = open == 1 ? '1 vaga restante' : '$open vagas restantes';
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.teal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              'ScapeMatch',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.roomName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.houseName} · ${group.cityName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(formatSession(group.startsAt)),
                const SizedBox(height: 4),
                Text(
                  spots,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
