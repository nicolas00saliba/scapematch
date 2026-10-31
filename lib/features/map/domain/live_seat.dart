import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

/// Alguém sentou num grupo de exemplo. A faixa usa o nome e a sala.
class LiveSeat {
  const LiveSeat({
    required this.groupId,
    required this.houseId,
    required this.roomName,
    required this.displayName,
  });

  final String groupId;
  final String houseId;
  final String roomName;
  final String displayName;
}

/// Grupo que ainda aceita um convidado fictício.
///
/// Prefere quem ainda está se formando. Empate fica com o horário mais cedo.
Group? pickSeatTarget(List<Group> groups, DateTime now) {
  final open = [
    for (final group in groups)
      if (_canSeat(group, now)) group,
  ];
  open.sort((a, b) {
    final aForming = a.phaseAt(now) == GroupPhase.forming ? 0 : 1;
    final bForming = b.phaseAt(now) == GroupPhase.forming ? 0 : 1;
    final phase = aForming.compareTo(bForming);
    if (phase != 0) {
      return phase;
    }
    return a.startsAt.compareTo(b.startsAt);
  });
  if (open.isEmpty) {
    return null;
  }
  return open.first;
}

bool _canSeat(Group group, DateTime now) {
  if (group.phaseAt(now) == GroupPhase.cancelled) {
    return false;
  }
  if (!now.isBefore(group.startsAt)) {
    return false;
  }
  if (GroupRules.hasEnded(endsAt: group.endsAt, now: now)) {
    return false;
  }
  return group.openSeats > 0;
}
