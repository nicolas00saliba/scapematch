import 'package:dominio/dominio.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/partner/domain/partner_statement.dart';

/// O que a casa vê numa abertura do Parceiro.
class PartnerSnapshot {
  const PartnerSnapshot({
    required this.house,
    required this.now,
    required this.grossCents,
    required this.commissionCents,
    required this.netCents,
    required this.reservedCents,
    required this.lines,
    required this.groups,
    required this.rooms,
    required this.slotsByRoom,
    required this.absenceCounts,
    required this.absenceMarks,
    required this.standings,
  });

  final EscapeHouse house;
  final DateTime now;
  final int grossCents;
  final int commissionCents;
  final int netCents;
  final int reservedCents;
  final List<StatementLine> lines;
  final List<Group> groups;
  final List<EscapeRoom> rooms;
  final Map<String, List<TimeSlot>> slotsByRoom;

  /// Faltas da pessoa, em qualquer grupo desta casa.
  final Map<String, int> absenceCounts;

  /// Chaves `grupo|jogador` já marcadas.
  final Set<String> absenceMarks;

  /// Resultado da [AbsencePolicy] para cada pessoa que já tem falta.
  final Map<String, AbsenceStanding> standings;

  int absenceCount(String playerId) => absenceCounts[playerId] ?? 0;

  bool markedAbsent(String groupId, String playerId) {
    return absenceMarks.contains('$groupId|$playerId');
  }

  AbsenceStanding standingOf(String playerId) {
    return standings[playerId] ?? AbsenceStanding.clear;
  }
}
