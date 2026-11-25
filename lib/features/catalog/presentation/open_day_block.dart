import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/domain/open_schedule.dart';

/// Quadrante da data. Só recebe dias que já têm horário livre.
class OpenDayBlock extends StatelessWidget {
  const OpenDayBlock({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelected,
    required this.emptyMessage,
    this.loading = false,
  });

  final List<DateTime> days;
  final DateTime? selected;
  final ValueChanged<DateTime>? onSelected;
  final String emptyMessage;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: AppKeys.openDays,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (loading)
              const LinearProgressIndicator()
            else if (days.isEmpty)
              Text(
                emptyMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final day in days)
                    ChoiceChip(
                      key: AppKeys.openDay(day.year, day.month, day.day),
                      label: Text(formatOpenDay(day)),
                      selected:
                          selected != null && sameCalendarDay(selected!, day),
                      onSelected: onSelected == null
                          ? null
                          : (_) => onSelected!(day),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
