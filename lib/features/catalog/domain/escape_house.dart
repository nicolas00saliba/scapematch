/// A fictional escape-room venue inside one city.
class EscapeHouse {
  const EscapeHouse({
    required this.id,
    required this.cityId,
    required this.name,
    required this.neighborhood,
    this.streetAddress = 'Rua de exemplo, 100',
  });

  final String id;
  final String cityId;
  final String name;
  final String neighborhood;

  /// Endereço fictício. O mapa usa isso junto com o bairro e a cidade.
  final String streetAddress;
}
