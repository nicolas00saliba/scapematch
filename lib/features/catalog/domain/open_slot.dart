import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';

/// Um horário livre de uma sala, no dia do calendário da casa.
class OpenSlot {
  const OpenSlot({
    required this.slot,
    required this.day,
    required this.timeLabel,
  });

  final TimeSlot slot;

  /// Dia civil, sem hora. No banco é America/Sao_Paulo. Na demonstração
  /// é o relógio local da amostra, o mesmo dos outros horários de exemplo.
  final DateTime day;

  /// Hora de parede, `HH:mm`, no fuso da casa.
  final String timeLabel;
}

/// Horários livres de uma sala no dia escolhido.
class RoomOpenings {
  const RoomOpenings({required this.room, required this.slots});

  final EscapeRoom room;
  final List<OpenSlot> slots;
}

/// Grupo que ainda ocupa a sala naquele instante.
class SlotOccupancy {
  const SlotOccupancy({
    required this.slotId,
    required this.roomId,
    required this.startsAt,
    required this.cancelled,
  });

  final String slotId;
  final String roomId;
  final DateTime startsAt;
  final bool cancelled;
}
