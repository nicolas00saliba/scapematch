/// Quantas faltas avisam e quantas bloqueiam. Os números são configuração.
class AbsencePolicy {
  AbsencePolicy({this.warningAt = 1, this.blockAt = 3}) {
    if (warningAt < 1 || blockAt <= warningAt) {
      throw ArgumentError('O bloqueio precisa vir depois do aviso.');
    }
  }

  final int warningAt;
  final int blockAt;
}

enum AbsenceStanding { clear, warned, blocked }

class AbsenceRecord {
  const AbsenceRecord({
    required this.playerId,
    required this.groupId,
    required this.houseId,
  });

  final String playerId;
  final String groupId;
  final String houseId;
}

/// Faltas marcadas pela casa. A mesma pessoa no mesmo grupo conta uma vez.
class AbsenceBook {
  AbsenceBook({AbsencePolicy? policy}) : policy = policy ?? AbsencePolicy();

  final AbsencePolicy policy;
  final List<AbsenceRecord> _records = [];

  List<AbsenceRecord> get records => List.unmodifiable(_records);

  /// Registra a falta. Repetir o mesmo grupo não soma de novo.
  AbsenceStanding markAbsent({
    required String playerId,
    required String groupId,
    required String houseId,
  }) {
    if (playerId.trim().isEmpty || groupId.trim().isEmpty) {
      throw ArgumentError('Jogador e grupo são obrigatórios.');
    }
    final already = _records.any(
      (record) => record.playerId == playerId && record.groupId == groupId,
    );
    if (!already) {
      _records.add(
        AbsenceRecord(playerId: playerId, groupId: groupId, houseId: houseId),
      );
    }
    return standingOf(playerId);
  }

  int countOf(String playerId) {
    return _records.where((record) => record.playerId == playerId).length;
  }

  AbsenceStanding standingOf(String playerId) {
    final count = countOf(playerId);
    if (count >= policy.blockAt) {
      return AbsenceStanding.blocked;
    }
    if (count >= policy.warningAt) {
      return AbsenceStanding.warned;
    }
    return AbsenceStanding.clear;
  }
}
