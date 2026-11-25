import 'package:scapematch/core/time/region_time.dart';
import 'package:scapematch/features/catalog/domain/open_slot.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

/// Horários em que ainda dá para reservar.
///
/// Sessão ativa e no futuro. Com 1 h ou menos ela entra marcada
/// [OpenSlot.nearStart]. Some só quando um grupo não cancelado já
/// encheu as vagas pagas até o máximo do host.
List<OpenSlot> bookableSlots({
  required Iterable<TimeSlot> slots,
  required Iterable<SlotOccupancy> occupancy,
  required DateTime now,
  RegionTime region = RegionTime.current,
}) {
  final open =
      <OpenSlot>[
        for (final slot in slots)
          if (_bookable(slot, occupancy, now))
            OpenSlot(
              slot: slot,
              day: region.calendarDay(slot.startsAt),
              timeLabel: region.hourMinute(slot.startsAt),
              nearStart: GroupRules.tooCloseToCreate(
                startsAt: slot.startsAt,
                now: now,
              ),
              openGroupId: _openGroup(slot, occupancy)?.groupId,
              spotsLeft: _spotsLeft(slot, occupancy),
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
  return RegionTime.current.calendarDay(instant);
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
  for (final group in occupancy) {
    if (!_same(group, slot)) continue;
    if (group.full) return false;
  }
  return true;
}

SlotOccupancy? _openGroup(TimeSlot slot, Iterable<SlotOccupancy> occupancy) {
  for (final group in occupancy) {
    if (!_same(group, slot) || group.cancelled || group.full) continue;
    if (group.groupId != null) return group;
  }
  return null;
}

int? _spotsLeft(TimeSlot slot, Iterable<SlotOccupancy> occupancy) {
  final group = _openGroup(slot, occupancy);
  if (group == null) return null;
  final left = group.totalSpots - group.paidSpots;
  return left < 0 ? 0 : left;
}

bool _same(SlotOccupancy group, TimeSlot slot) {
  if (group.cancelled) return false;
  final sameSlot = group.slotId.isNotEmpty && group.slotId == slot.id;
  final sameInstant =
      group.roomId == slot.roomId &&
      group.startsAt.isAtSameMomentAs(slot.startsAt);
  return sameSlot || sameInstant;
}
