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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SlotChip(
                            slot: slot,
                            selected: slot.slot.id == selectedSlotId,
                            onSelected: onSelected == null
                                ? null
                                : () => onSelected!(slot),
                          ),
                          if (slot.nearStart)
                            IconButton(
                              key: AppKeys.openSlotInfo(slot.slot.id),
                              tooltip: 'Sem reembolso se cancelar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _warnNearStart(context),
                              icon: Icon(
                                Icons.info_outline,
                                size: 18,
                                color: scheme.error,
                              ),
                            ),
                        ],
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

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.selected,
    required this.onSelected,
  });

  final OpenSlot slot;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final near = slot.nearStart;
    return ChoiceChip(
      key: AppKeys.openSlot(slot.slot.id),
      label: Text(slot.timeLabel),
      selected: selected,
      onSelected: onSelected == null ? null : (_) => onSelected!(),
      showCheckmark: !near,
      side: near ? BorderSide(color: scheme.error, width: 1.4) : null,
      labelStyle: TextStyle(
        color: near ? scheme.error : null,
        fontWeight: FontWeight.w700,
      ),
      color: near ? WidgetStatePropertyAll(scheme.errorContainer) : null,
    );
  }
}

void _warnNearStart(BuildContext context) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        key: AppKeys.openSlotHint,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              'Reservar neste horário pode não ter reembolso se você cancelar.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ),
      );
    },
  );
}
