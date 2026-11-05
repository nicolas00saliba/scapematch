/// 11 dígitos com os dois verificadores. CPF repetido não vale.
String? playerCpfDigits(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^\d{11}$').hasMatch(digits)) return null;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return null;
  int digit(int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += int.parse(digits[i]) * (length + 1 - i);
    }
    final mod = (sum * 10) % 11;
    return mod == 10 ? 0 : mod;
  }

  if (digit(9) != int.parse(digits[9]) || digit(10) != int.parse(digits[10])) {
    return null;
  }
  return digits;
}
