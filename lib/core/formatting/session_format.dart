import 'package:intl/intl.dart';

/// Example: "Sáb, 7 de nov · 18:30".
String formatSession(DateTime dateTime) {
  final raw = DateFormat("EEE, d 'de' MMM '·' HH:mm", 'pt_BR').format(dateTime);
  if (raw.isEmpty) {
    return raw;
  }
  return raw[0].toUpperCase() + raw.substring(1);
}

/// "Começa em 1 h 30 min", "Já começou", or "Sessão encerrada".
///
/// [now] comes from the injected clock. This function does not read the
/// wall clock itself.
String formatStartsIn({
  required DateTime startsAt,
  required DateTime endsAt,
  required DateTime now,
}) {
  if (!now.isBefore(endsAt)) {
    return 'Sessão encerrada';
  }
  if (!now.isBefore(startsAt)) {
    return 'Já começou';
  }
  final minutes = startsAt.difference(now).inMinutes;
  if (minutes < 60) {
    final shown = minutes < 1 ? 1 : minutes;
    return shown == 1 ? 'Começa em 1 min' : 'Começa em $shown min';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours < 48) {
    if (rest == 0) {
      return 'Começa em $hours h';
    }
    return 'Começa em $hours h $rest min';
  }
  final days = hours ~/ 24;
  final remHours = hours % 24;
  final dayLabel = days == 1 ? '1 dia' : '$days dias';
  if (remHours == 0) {
    return 'Começa em $dayLabel';
  }
  return 'Começa em $dayLabel e $remHours h';
}
