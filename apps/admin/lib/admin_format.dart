String reais(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = _thousands(abs ~/ 100);
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ $whole,$frac';
}

String percentBps(int bps) {
  final whole = bps ~/ 100;
  final frac = bps % 100;
  if (frac == 0) return '$whole%';
  return '$whole,${(frac ~/ 10)}%';
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
