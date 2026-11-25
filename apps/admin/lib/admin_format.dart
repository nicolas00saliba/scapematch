String reais(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = _thousands(abs ~/ 100);
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ $whole,$frac';
}

String percentBps(int bps) => '${percentInput(bps)}%';

/// Texto do campo: 2000 vira "20" e 2250 vira "22,5".
String percentInput(int bps) {
  final whole = bps ~/ 100;
  final frac = (bps % 100).abs();
  if (frac == 0) return '$whole';
  if (frac % 10 == 0) return '$whole,${frac ~/ 10}';
  return '$whole,${frac.toString().padLeft(2, '0')}';
}

/// Percentual digitado (22,5 ou 22.5) em pontos-base. Fora de 0% a 30%,
/// ou com mais de duas casas, devolve nulo.
int? bpsFromPercent(String raw) {
  final text = raw
      .trim()
      .replaceAll('%', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  if (value == null) return null;
  final bps = (value * 100).round();
  if ((bps - value * 100).abs() > 0.001) return null;
  if (bps < 0 || bps > 3000) return null;
  return bps;
}

String _thousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// Relógio de Brasília (America/Sao_Paulo, UTC-3 o ano todo desde 2019).
/// O painel mostra a hora de Curitiba, não a do aparelho.
const brasiliaOffset = Duration(hours: 3);

/// Data e hora de parede em Brasília, num DateTime marcado como UTC.
DateTime brasiliaWall(DateTime value) => value.toUtc().subtract(brasiliaOffset);

/// Início do mês corrente em Brasília, em UTC.
DateTime brasiliaMonthStartUtc(DateTime now) {
  final wall = brasiliaWall(now);
  return DateTime.utc(wall.year, wall.month).add(brasiliaOffset);
}

String whenLabel(DateTime? value) {
  if (value == null) return '—';
  final local = brasiliaWall(value);
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
