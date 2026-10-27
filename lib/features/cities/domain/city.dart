/// A city the player can search in. The app never assumes a default city.
class City {
  const City({
    required this.id,
    required this.name,
    required this.stateCode,
    required this.stateName,
  });

  final String id;
  final String name;
  final String stateCode;
  final String stateName;
}
