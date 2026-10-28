/// Valor em centavos. R$ 40,00 é `Money(4000)`.
///
/// Não existe campo de reais solto no modelo, para o arredondamento não
/// mudar o saldo. A tela formata com `formatPrice`.
class Money {
  const Money(this.cents);

  final int cents;

  Money operator +(Money other) => Money(cents + other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents;

  @override
  String toString() => 'Money($cents)';
}
