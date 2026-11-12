/// Tempo de escape por sala. O ranking público mostra o menor tempo
/// de quem escapou. Quem não escapou fica só no histórico.
library;

enum RoomTimeMedal { gold, silver, bronze }

const roomTimeDefaultGroup = 'Grupo';
const roomTimeNameLimit = 40;

RoomTimeMedal? medalForPlace(int? place) {
  return switch (place) {
    1 => RoomTimeMedal.gold,
    2 => RoomTimeMedal.silver,
    3 => RoomTimeMedal.bronze,
    _ => null,
  };
}

String medalLabel(RoomTimeMedal medal) {
  return switch (medal) {
    RoomTimeMedal.gold => 'Ouro',
    RoomTimeMedal.silver => 'Prata',
    RoomTimeMedal.bronze => 'Bronze',
  };
}

String roomTimePlaceLabel(int place) => '$placeº';

/// Relógio da sala, sempre mm:ss. Os minutos passam de 59 quando a
/// duração da sala passa de uma hora.
String formatRoomClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// Tempo gasto em mm:ss e, entre parênteses, os minutos que sobraram.
/// Minutos arredondados para baixo. Menos de um minuto sai em segundos.
String formatRoomTimeLine(int elapsedSeconds, int remainingSeconds) {
  final safe = remainingSeconds < 0 ? 0 : remainingSeconds;
  final rest = safe < 60
      ? 'Restavam $safe s'
      : 'Restavam ${safe ~/ 60} min';
  return '${formatRoomClock(elapsedSeconds)} ($rest)';
}

int remainingSeconds({
  required int durationMinutes,
  required int elapsedSeconds,
}) {
  final duration = durationMinutes * 60;
  final left = duration - elapsedSeconds;
  return left < 0 ? 0 : left;
}

String formatRoomDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// Vazio vale o nome padrão. Texto preenchido devolve a mensagem de erro.
String? roomTimeNameError(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return null;
  if (name.length < 2 || name.length > roomTimeNameLimit) {
    return 'O nome do grupo fica entre 2 e 40 caracteres.';
  }
  if (_hasBlockedSymbol(name)) {
    return 'O nome do grupo usa letras, números, espaço, apóstrofo ou hífen.';
  }
  if (roomTimeBlocked(name)) {
    return 'Escolha outro nome para o grupo.';
  }
  return null;
}

String roomTimeNameOrDefault(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return roomTimeDefaultGroup;
  return name;
}

/// Primeiro nome ou apelido. E-mail, vazio e palavrão viram Jogador.
String firstLabel(String raw) {
  final token = raw.trim().split(RegExp(r'\s+')).first;
  if (token.isEmpty || token.contains('@') || roomTimeBlocked(token)) {
    return 'Jogador';
  }
  if (token.length <= 24) return token;
  return token.substring(0, 24);
}

bool roomTimeBlocked(String raw) {
  final tokens = _fold(raw)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty);
  return tokens.any(_blocked.contains);
}

const _blocked = {
  'porra',
  'caralho',
  'foda',
  'foder',
  'fodase',
  'puta',
  'puto',
  'buceta',
  'cu',
  'merda',
  'bosta',
  'viado',
  'viada',
  'desgraca',
  'arrombado',
  'arrombada',
  'cacete',
  'piranha',
  'vadia',
  'fuck',
  'shit',
  'bitch',
  'asshole',
};

bool _hasBlockedSymbol(String name) {
  if (name.runes.any((rune) => rune < 32)) return true;
  return RegExp(r'''[@#$%&*_+=<>/\\|\[\]{}~`^,.;:!?"()]''').hasMatch(name);
}

String _fold(String value) {
  const from = 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ';
  const to = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn';
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString().toLowerCase();
}

/// Uma linha de ranking ou do histórico do jogador.
class RoomTimeLine {
  const RoomTimeLine({
    required this.groupName,
    required this.elapsedSeconds,
    required this.remainingSeconds,
    required this.playedOn,
    required this.members,
    required this.escaped,
    this.place,
    this.entryId,
    this.groupId,
    this.roomName,
    this.venueName,
    this.memberIds = const [],
    this.nameChosen = false,
  });

  final int? place;
  final String groupName;
  final int elapsedSeconds;
  final int remainingSeconds;
  final DateTime playedOn;
  final List<String> members;
  final bool escaped;
  final String? entryId;
  final String? groupId;
  final String? roomName;
  final String? venueName;

  /// Contas ligadas à linha, na mesma ordem de [members]. Vazio no ranking público.
  final List<String> memberIds;

  /// O grupo já escolheu o nome. Lançar ou editar o tempo não troca esse nome.
  final bool nameChosen;

  RoomTimeMedal? get medal => medalForPlace(escaped ? place : null);

  String get clockLine => formatRoomTimeLine(elapsedSeconds, remainingSeconds);

  String get membersLine => members.join(' · ');
}
