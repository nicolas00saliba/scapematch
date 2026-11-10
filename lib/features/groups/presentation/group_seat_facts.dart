import 'package:flutter/material.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

/// Faixa do host e o status: falta confirmar, confirmado ou lotado.
///
/// Na grade da Home no site ([dense]), ficam a faixa, a barra e o status.
class GroupSeatFacts extends StatelessWidget {
  const GroupSeatFacts({
    super.key,
    required this.group,
    this.compact = false,
    this.dense = false,
  });

  final Group group;
  final bool compact;

  /// Grade da Home no site: só vagas e progresso, numa faixa curta.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = group.totalSpots == 0
        ? 0.0
        : (group.filledSpots / group.totalSpots).clamp(0, 1).toDouble();
    final count = GroupMessages.playerBand(
      filled: group.filledSpots,
      minimum: group.minimumSpots,
      maximum: group.totalSpots,
    );
    final status = GroupMessages.bandStatus(
      filled: group.filledSpots,
      minimum: group.minimumSpots,
      maximum: group.totalSpots,
      confirmed: group.isConfirmed,
    );
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: dense ? 4 : (compact ? 6 : 8),
        backgroundColor: scheme.primaryContainer,
        color: group.isFull ? scheme.onSurfaceVariant : scheme.primary,
      ),
    );
    if (dense) {
      final line = theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        height: 1.15,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count, maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: line?.copyWith(color: scheme.secondary),
          ),
          const SizedBox(height: 4),
          bar,
        ],
      );
    }
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );
    final gap = 6.0;
    final countStyle = compact
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count,
          style: countStyle?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: gap),
        bar,
        SizedBox(height: gap),
        Text(
          GroupMessages.roomBounds(
            minimum: group.roomMinimum,
            maximum: group.roomCapacity,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secondary,
        ),
        const SizedBox(height: 2),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
