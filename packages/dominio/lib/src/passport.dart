/// Passaporte de salas. Um carimbo por sala, marcos em pontos de
/// desconto e o fechamento de uma casa. O carimbo sai quando a reserva
/// está paga e a casa confirma o comparecimento. A versão provisória
/// usa os números de [PassportRules.provisional]. O banco guarda os
/// mesmos campos e pode mudá-los sem recompilar o app.
class PassportRules {
  const PassportRules({
    required this.countMilestones,
    required this.housePoints,
  });

  /// Salas diferentes e os pontos daquele marco. A lista cresce.
  final List<PassportCountMilestone> countMilestones;

  /// Pontos ao fechar todas as salas de uma casa. 0 desliga.
  /// Só vale para casa com duas salas ou mais, uma vez por casa.
  final int housePoints;

  static const provisional = PassportRules(
    countMilestones: [
      PassportCountMilestone(rooms: 5, points: 500),
      PassportCountMilestone(rooms: 10, points: 1000),
      PassportCountMilestone(rooms: 25, points: 3000),
    ],
    housePoints: 300,
  );
}

class PassportCountMilestone {
  const PassportCountMilestone({required this.rooms, required this.points});

  final int rooms;
  final int points;
}

/// Carimbo já conquistado. [playCount] sobe quando a pessoa joga
/// a mesma sala de novo. O carimbo continua sendo um só.
class RoomStamp {
  const RoomStamp({
    required this.roomId,
    required this.venueId,
    required this.playCount,
  });

  final String roomId;
  final String venueId;
  final int playCount;

  bool get active => playCount > 0;
}

/// Marco que ainda está pago. [roomIds] guarda as salas que fecharam
/// a casa. Um marco de contagem deixa a lista vazia.
class OpenPassportMilestone {
  const OpenPassportMilestone({required this.key, required this.roomIds});

  final String key;
  final List<String> roomIds;
}

class PlannedPassportGrant {
  const PlannedPassportGrant({
    required this.key,
    required this.points,
    required this.roomIds,
  });

  final String key;
  final int points;
  final List<String> roomIds;
}

class PassportMilestonePlan {
  const PassportMilestonePlan({required this.grant, required this.reverse});

  final List<PlannedPassportGrant> grant;
  final List<String> reverse;
}

/// Próxima vez que a pessoa joga a sala. A cobrança que já entrou
/// não soma de novo.
int nextPassportPlayCount({
  required int? current,
  required bool chargeAlreadyCounted,
}) {
  if (chargeAlreadyCounted) return current ?? 1;
  return (current ?? 0) + 1;
}

String passportCountKey(int rooms) => 'count:$rooms';

String passportHouseKey(String venueId) => 'house:$venueId';

/// Decide o que lançar e o que estornar. Não grava nada.
///
/// Casa nova que aparece depois do marco não desfaz o prêmio: as salas
/// gravadas no marco é que precisam continuar carimbadas. Uma sala a
/// menos, ou o marco de contagem que deixou de caber, estorna.
PassportMilestonePlan planPassportMilestones({
  required PassportRules rules,
  required List<RoomStamp> stamps,
  required Map<String, List<String>> roomsByVenue,
  required List<OpenPassportMilestone> open,
}) {
  final active = <String, RoomStamp>{
    for (final stamp in stamps)
      if (stamp.active) stamp.roomId: stamp,
  };
  final desired = <String, PlannedPassportGrant>{};

  final seenRooms = <int>{};
  for (final rule in rules.countMilestones) {
    if (rule.points <= 0 || rule.rooms <= 0 || !seenRooms.add(rule.rooms)) {
      continue;
    }
    if (active.length >= rule.rooms) {
      final key = passportCountKey(rule.rooms);
      desired[key] = PlannedPassportGrant(
        key: key,
        points: rule.points,
        roomIds: const [],
      );
    }
  }

  if (rules.housePoints > 0) {
    final venues = <String>{
      for (final stamp in active.values) stamp.venueId,
      for (final milestone in open)
        if (milestone.key.startsWith('house:')) milestone.key.substring(6),
    };
    for (final venueId in venues) {
      final key = passportHouseKey(venueId);
      final current = open.where((item) => item.key == key).toList();
      final kept = current.isEmpty
          ? null
          : current.first.roomIds.where(active.containsKey).length ==
                current.first.roomIds.length &&
              current.first.roomIds.length >= 2;
      if (kept == true) {
        desired[key] = PlannedPassportGrant(
          key: key,
          points: rules.housePoints,
          roomIds: current.first.roomIds,
        );
        continue;
      }
      final rooms = roomsByVenue[venueId] ?? const <String>[];
      if (rooms.length >= 2 && rooms.every(active.containsKey)) {
        desired[key] = PlannedPassportGrant(
          key: key,
          points: rules.housePoints,
          roomIds: List<String>.of(rooms),
        );
      }
    }
  }

  final openKeys = {for (final milestone in open) milestone.key};
  return PassportMilestonePlan(
    grant: [
      for (final entry in desired.entries)
        if (!openKeys.contains(entry.key)) entry.value,
    ],
    reverse: [
      for (final milestone in open)
        if (!desired.containsKey(milestone.key)) milestone.key,
    ],
  );
}

/// A casa confirma o comparecimento a partir do horário da sessão,
/// só de quem pagou e não foi estornado. Nulo quando a confirmação pode seguir.
String? sessionCheckinBlock({
  required DateTime now,
  required DateTime startsAt,
  required bool paid,
  required bool refunded,
  required bool seatCancelled,
  required bool groupCancelled,
}) {
  if (groupCancelled) {
    return 'Grupo cancelado não confirma comparecimento.';
  }
  if (now.isBefore(startsAt)) {
    return 'A sessão ainda não começou.';
  }
  if (seatCancelled) {
    return 'Essa pessoa não está no grupo.';
  }
  if (!paid || refunded) {
    return 'Só confirma quem pagou e não foi estornado.';
  }
  return null;
}
