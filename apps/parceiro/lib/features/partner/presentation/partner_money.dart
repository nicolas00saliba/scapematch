/// Lê "120" como R$ 120,00 e "120,50" como R$ 120,50.
int? parseReais(String raw) {
  final text = raw.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (text.isEmpty) {
    return null;
  }
  final normalized = text.contains(',')
      ? text.replaceAll('.', '').replaceAll(',', '.')
      : text;
  final value = double.tryParse(normalized);
  if (value == null || value <= 0) {
    return null;
  }
  return (value * 100).round();
}

/// "11500" centavos vira "115,00", para o campo de preço.
String reaisField(int cents) {
  final whole = cents ~/ 100;
  final fraction = (cents.abs() % 100).toString().padLeft(2, '0');
  return '$whole,$fraction';
}
