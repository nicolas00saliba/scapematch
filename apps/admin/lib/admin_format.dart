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
  final text = raw.trim().replaceAll('%', '').replaceAll(' ', '').replaceAll(',', '.');
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

String whenLabel(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
