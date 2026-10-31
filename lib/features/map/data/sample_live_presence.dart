import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/map/domain/live_seat.dart';

/// De quanto em quanto tempo um avatar de exemplo senta.
///
/// O timer só existe enquanto o mapa está na tela. O teste avança esse
/// intervalo no relógio falso do widget; a lista da Home não dispara sozinha.
const livePresenceInterval = Duration(seconds: 5);

/// Senta um convidado fictício no banco em memória.
///
/// Isto não é o backend. Quando o Supabase entrar, o mapa deixa de chamar
/// [takeSeat] e passa a ouvir o canal Realtime de `group_members`, descrito
/// em `docs/SUPABASE_ESQUEMA.md`. A faixa e os pinos continuam lendo a mesma
/// lista de grupos.
class SampleLivePresence {
  SampleLivePresence({required this.database, required this.clock});

  final FakeDatabase database;
  final Clock clock;

  var _nameCursor = 0;

  static const _names = <String>[
    'Lia',
    'Otto',
    'Nara',
    'Ivo',
    'Bela',
    'Dora',
    'Enzo',
    'Fran',
    'Guto',
    'Hana',
    'Igor',
    'Júlia',
  ];

  /// Devolve nulo quando a cidade não tem vaga aberta antes do início.
  LiveSeat? takeSeat(String cityId) {
    final now = clock.now();
    final target = pickSeatTarget([
      for (final group in database.groups)
        if (group.cityId == cityId) group,
    ], now);
    if (target == null) {
      return null;
    }
    final index = database.groups.indexWhere((group) => group.id == target.id);
    if (index < 0) {
      return null;
    }
    final name = _nextName(target.participants.map((p) => p.displayName));
    final updated = target.copyWith(
      filledSpots: target.filledSpots + 1,
      participants: [
        ...target.participants,
        Participant(
          id: database.nextParticipantId(),
          displayName: name,
          isCreator: false,
          isLocalUser: false,
        ),
      ],
    );
    database.groups[index] = updated;
    return LiveSeat(
      groupId: updated.id,
      houseId: updated.houseId,
      roomName: updated.roomName,
      displayName: name,
    );
  }

  String _nextName(Iterable<String> taken) {
    final used = taken.toSet();
    for (var attempt = 0; attempt < _names.length; attempt++) {
      final name = _names[_nameCursor % _names.length];
      _nameCursor += 1;
      if (!used.contains(name)) {
        return name;
      }
    }
    _nameCursor += 1;
    return 'Convidado $_nameCursor';
  }
}
