/// Bandeira que a tela pode mostrar. Não é o número do cartão.
enum CardBrand { visa, mastercard, elo, other }

/// Cartão já tokenizado, só com o que é seguro mostrar.
///
/// [last4] são quatro dígitos. Não há número completo, validade nem CVV
/// neste modelo. Um cartão real chega como token do provedor; este objeto
/// guarda o apelido e a bandeira para a lista.
class PaymentMethod {
  PaymentMethod({
    required this.id,
    required this.brand,
    required String last4,
    required this.nickname,
  }) : last4 = _requireLast4(last4);

  final String id;
  final CardBrand brand;
  final String last4;
  final String nickname;

  static String _requireLast4(String value) {
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'last4',
        'use apenas os quatro últimos dígitos',
      );
    }
    return value;
  }
}

/// Nome curto da bandeira na lista.
String cardBrandLabel(CardBrand brand) {
  return switch (brand) {
    CardBrand.visa => 'Visa',
    CardBrand.mastercard => 'Mastercard',
    CardBrand.elo => 'Elo',
    CardBrand.other => 'Cartão',
  };
}
