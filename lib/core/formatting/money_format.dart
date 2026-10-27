import 'package:intl/intl.dart';

/// Formats a fictional price stored in cents, for example 10900 → "R$ 109,00".
String formatPrice(int priceCents) {
  final format = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );
  return format.format(priceCents / 100);
}
