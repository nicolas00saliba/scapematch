/// A fictional escape-room venue inside one city.
class EscapeHouse {
  const EscapeHouse({
    required this.id,
    required this.cityId,
    required this.name,
    required this.neighborhood,
    required this.latitude,
    required this.longitude,
    this.streetAddress = 'Rua de exemplo, 100',
    this.receivesPayments = true,
  });

  final String id;
  final String cityId;
  final String name;
  final String neighborhood;

  /// Endereço fictício. O mapa usa isso junto com o bairro e a cidade.
  final String streetAddress;

  /// Ponto fictício no bairro, para o mapa. Não é o endereço de uma casa real.
  final double latitude;
  final double longitude;

  /// Falso quando a casa aprovada ainda não tem subconta. A demonstração
  /// segue verdadeira para não esconder sala de exemplo.
  final bool receivesPayments;
}

/// A vitrine sem a coluna continua visível. `false` tira a casa da criação.
bool venueReceivesGroups(Map<dynamic, dynamic> row) {
  if (!row.containsKey('receives_payments')) return true;
  return row['receives_payments'] != false;
}
