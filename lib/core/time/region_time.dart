/// Fuso do calendário da casa e do jogador.
///
/// Hoje só existe Curitiba: `America/Sao_Paulo`, UTC−3, sem horário de
/// verão. Uma configuração futura (Brasil ou mundo), escolhida pela
/// pessoa, troca [zoneId]. Não há tela dessa escolha agora.
class RegionTime {
  const RegionTime({this.zoneId = saoPaulo});

  static const saoPaulo = 'America/Sao_Paulo';

  /// A região em vigor. O único valor hoje é [saoPaulo].
  static const current = RegionTime();

  final String zoneId;

  /// Dia civil no fuso da região.
  DateTime calendarDay(DateTime instant) {
    final wall = wallClock(instant);
    return DateTime(wall.year, wall.month, wall.day);
  }

  /// Hora de parede `HH:mm` no fuso da região.
  String hourMinute(DateTime instant) {
    final wall = wallClock(instant);
    final hour = wall.hour.toString().padLeft(2, '0');
    final minute = wall.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Instante UTC de uma hora de parede nesta região.
  ///
  /// [wall] guarda ano, mês, dia, hora e minuto escolhidos. O fuso do
  /// aparelho não entra na conta.
  DateTime toUtcInstant(DateTime wall) {
    final offset = _offset(zoneId);
    return DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    ).subtract(offset);
  }

  /// Hora de parede. Um [DateTime] local da demonstração já é a hora da
  /// casa. Um instante UTC (o banco) desce para o fuso da região.
  DateTime wallClock(DateTime instant) {
    if (!instant.isUtc) {
      return instant;
    }
    final shifted = instant.add(_offset(zoneId));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Deslocamento da hora de parede em relação ao UTC.
  /// São Paulo é −3 h. Outro [zoneId] ainda não existe.
  Duration _offset(String zone) {
    if (zone == saoPaulo) {
      return const Duration(hours: -3);
    }
    return const Duration(hours: -3);
  }
}
