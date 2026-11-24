import 'package:intl/intl.dart';
import 'package:scapematch/features/catalog/domain/open_slot.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

/// Horários em que ainda dá para criar um grupo.
///
/// A mesma regra do `create_group`: sessão ativa, no futuro, com mais de
/// 1 h de antecedência, e sem grupo ativo na sala naquele instante.
List<OpenSlot> bookableSlots({
  required Iterable<TimeSlot> slots,
  required Iterable<SlotOccupancy> occupancy,
  required DateTime now,
}) {
  final open =
      <OpenSlot>[
        for (final slot in slots)
          if (_bookable(slot, occupancy, now))
            OpenSlot(
              slot: slot,
              day: calendarDay(slot.startsAt),
              timeLabel: DateFormat('HH:mm', 'pt_BR').format(slot.startsAt),
            ),
      ]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        if (byDay != 0) return byDay;
        return a.slot.startsAt.compareTo(b.slot.startsAt);
      });
  return open;
}

/// Dias, em ordem, que têm pelo menos um horário livre.
List<DateTime> openDaysOf(Iterable<OpenSlot> slots) {
  final days = <DateTime>[];
  for (final slot in slots) {
    if (days.any((day) => sameCalendarDay(day, slot.day))) continue;
    days.add(slot.day);
  }
  days.sort();
  return days;
}

DateTime calendarDay(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// `2027-06-14` ou `2027-06-14T00:00:00` vira o dia civil, sem mudar o fuso.
DateTime calendarDayFromText(String raw) {
  final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final parts = date.split('-');
  if (parts.length != 3) {
    throw FormatException('Dia inválido: $raw');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

bool _bookable(TimeSlot slot, Iterable<SlotOccupancy> occupancy, DateTime now) {
  if (!slot.active) return false;
  if (GroupRules.hasStarted(startsAt: slot.startsAt, now: now)) return false;
  if (GroupRules.tooCloseToCreate(startsAt: slot.startsAt, now: now)) {
    return false;
  }
  for (final group in occupancy) {
    if (group.cancelled) continue;
    final sameSlot = group.slotId.isNotEmpty && group.slotId == slot.id;
    final sameInstant =
        group.roomId == slot.roomId &&
        group.startsAt.isAtSameMomentAs(slot.startsAt);
    if (sameSlot || sameInstant) return false;
  }
  return true;
}
