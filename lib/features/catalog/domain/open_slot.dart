import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';

/// Um horário livre de uma sala, no dia do calendário da casa.
class OpenSlot {
  const OpenSlot({
    required this.slot,
    required this.day,
    required this.timeLabel,
    this.nearStart = false,
    this.openGroupId,
    this.spotsLeft,
  });

  final TimeSlot slot;

  /// Dia civil, sem hora. No banco é America/Sao_Paulo. Na demonstração
  /// é o relógio local da amostra, o mesmo dos outros horários de exemplo.
  final DateTime day;

  /// Hora de parede, `HH:mm`, no fuso da casa.
  final String timeLabel;

  /// Falta 1 h ou menos. A reserva entra, em vermelho, sem reembolso
  /// se o jogador cancelar.
  final bool nearStart;

  /// Grupo já aberto nessa sala e nesse instante, ainda com vaga paga.
  final String? openGroupId;

  /// Vagas pagas que ainda cabem no máximo do host. Nulo quando não
  /// há grupo: quem cria define o máximo.
  final int? spotsLeft;
}

/// Horários livres de uma sala no dia escolhido.
class RoomOpenings {
  const RoomOpenings({required this.room, required this.slots});

  final EscapeRoom room;
  final List<OpenSlot> slots;
}

/// Grupo na sala naquele instante. A vaga some só quando as pagas
/// enchem o máximo do host.
class SlotOccupancy {
  const SlotOccupancy({
    required this.slotId,
    required this.roomId,
    required this.startsAt,
    required this.cancelled,
    this.groupId,
    this.totalSpots = 1,
    this.paidSpots = 0,
  });

  final String slotId;
  final String roomId;
  final DateTime startsAt;
  final bool cancelled;
  final String? groupId;
  final int totalSpots;

  /// `paid` e `reserved` (custódia autorizada). `pending` não ocupa.
  final int paidSpots;

  bool get full => !cancelled && paidSpots >= totalSpots;
}
