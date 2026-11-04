import 'package:dominio/dominio.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_statement.dart';

/// Bruto, comissão e líquido de um grupo. Reserva ainda não entrou no saldo.
class GroupMoney {
  const GroupMoney({
    required this.grossCents,
    required this.commissionCents,
    required this.netCents,
  });

  static const zero = GroupMoney(
    grossCents: 0,
    commissionCents: 0,
    netCents: 0,
  );

  final int grossCents;
  final int commissionCents;
  final int netCents;
}

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
    required this.moneyByGroup,
    required this.groups,
    required this.rooms,
    required this.slotsByRoom,
    required this.absenceCounts,
    required this.absenceMarks,
    required this.standings,
    required this.invoices,
    required this.fiscal,
  });

  final EscapeHouse house;
  final DateTime now;
  final int grossCents;
  final int commissionCents;
  final int netCents;
  final int reservedCents;
  final List<StatementLine> lines;
  final Map<String, GroupMoney> moneyByGroup;
  final List<Group> groups;

  GroupMoney moneyFor(String groupId) => moneyByGroup[groupId] ?? GroupMoney.zero;

  /// Nome da sala no catálogo. O grupo pode ter um título só do app do jogador.
  String roomNameFor(Group group) {
    for (final room in rooms) {
      if (room.id == group.roomId) {
        return room.name;
      }
    }
    return group.roomName;
  }
  final List<EscapeRoom> rooms;
  final Map<String, List<TimeSlot>> slotsByRoom;

  /// Faltas da pessoa, em qualquer grupo desta casa.
  final Map<String, int> absenceCounts;

  /// Chaves `grupo|jogador` já marcadas.
  final Set<String> absenceMarks;

  /// Resultado da [AbsencePolicy] para cada pessoa que já tem falta.
  final Map<String, AbsenceStanding> standings;

  /// Notas da casa: serviço para o jogador e comissão da ScapeMatch.
  final List<FiscalInvoiceView> invoices;

  /// Dados fiscais desta sessão. CPF fica sem emissão do serviço.
  final VenueFiscalProfile fiscal;

  int absenceCount(String playerId) => absenceCounts[playerId] ?? 0;

  bool markedAbsent(String groupId, String playerId) {
    return absenceMarks.contains('$groupId|$playerId');
  }

  AbsenceStanding standingOf(String playerId) {
    return standings[playerId] ?? AbsenceStanding.clear;
  }
}
