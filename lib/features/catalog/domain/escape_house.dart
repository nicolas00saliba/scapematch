/// A fictional escape-room venue inside one city.
class EscapeHouse {
  const EscapeHouse({
    required this.id,
    required this.cityId,
    required this.name,
    required this.neighborhood,
  });

  final String id;
  final String cityId;
  final String name;
  final String neighborhood;
}
