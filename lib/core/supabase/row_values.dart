DateTime? dateTimeOf(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.parse(text).toLocal();
}

DateTime? dateOnlyOf(Object? value) {
  final parsed = dateTimeOf(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

int intOf(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value == null) return fallback;
  return int.tryParse(value.toString()) ?? fallback;
}

double doubleOf(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value == null) return fallback;
  return double.tryParse(value.toString()) ?? fallback;
}

String textOf(Object? value) => value?.toString() ?? '';

String streetLine({required String street, required String number}) {
  final road = street.trim();
  final door = number.trim();
  if (road.isEmpty) return door;
  if (door.isEmpty || door == 'S/N') return road;
  return '$road, $door';
}
