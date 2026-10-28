/// "há 2 h", "há 20 min", "há 1 dia" ou "agora".
///
/// [now] vem do relógio injetado. Esta função não lê o relógio do aparelho.
String formatRelativeTime({
  required DateTime publishedAt,
  required DateTime now,
}) {
  final difference = now.difference(publishedAt);
  if (difference.isNegative || difference.inMinutes < 1) {
    return 'agora';
  }
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return minutes == 1 ? 'há 1 min' : 'há $minutes min';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return hours == 1 ? 'há 1 h' : 'há $hours h';
  }
  final days = difference.inDays;
  return days == 1 ? 'há 1 dia' : 'há $days dias';
}

const _shortMonths = <String>[
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// Data curta do cartão: "27 out". O ano não entra; a notícia é recente.
String formatShortDate(DateTime value) {
  return '${value.day} ${_shortMonths[value.month - 1]}';
}
