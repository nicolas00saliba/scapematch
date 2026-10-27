import 'package:intl/intl.dart';

/// Example: "Sáb, 7 de nov · 18:30".
String formatSession(DateTime dateTime) {
  final raw = DateFormat("EEE, d 'de' MMM '·' HH:mm", 'pt_BR').format(dateTime);
  if (raw.isEmpty) {
    return raw;
  }
  return raw[0].toUpperCase() + raw.substring(1);
}
