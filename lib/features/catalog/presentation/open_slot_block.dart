import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/domain/open_slot.dart';

/// Quadrante dos horários do dia, agrupados por sala.
class OpenSlotBlock extends StatelessWidget {
  const OpenSlotBlock({
    super.key,
    required this.day,
    required this.openings,
    required this.selectedSlotId,
    required this.onSelected,
  });

  final DateTime? day;
  final List<RoomOpenings> openings;
  final String? selectedSlotId;
  final ValueChanged<OpenSlot>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: AppKeys.openSlots,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Horários',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (day == null)
              Text(
                'Escolha a data para ver os horários.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              )
            else if (openings.isEmpty)
              Text(
                'Nenhum horário livre neste dia.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              )
            else
              for (var index = 0; index < openings.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                Text(
                  openings[index].room.name,
                  key: AppKeys.openRoom(openings[index].room.id),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in openings[index].slots)
                      ChoiceChip(
                        key: AppKeys.openSlot(slot.slot.id),
                        label: Text(slot.timeLabel),
                        selected: slot.slot.id == selectedSlotId,
                        onSelected: onSelected == null
                            ? null
                            : (_) => onSelected!(slot),
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}
