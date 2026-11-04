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

/// As cinco cidades do seletor. O banco tem as mesmas.
const knownCities = <City>[
  City(id: 'curitiba', name: 'Curitiba', stateCode: 'PR', stateName: 'Paraná'),
  City(
    id: 'sao-paulo',
    name: 'São Paulo',
    stateCode: 'SP',
    stateName: 'São Paulo',
  ),
  City(
    id: 'rio-de-janeiro',
    name: 'Rio de Janeiro',
    stateCode: 'RJ',
    stateName: 'Rio de Janeiro',
  ),
  City(
    id: 'belo-horizonte',
    name: 'Belo Horizonte',
    stateCode: 'MG',
    stateName: 'Minas Gerais',
  ),
  City(
    id: 'porto-alegre',
    name: 'Porto Alegre',
    stateCode: 'RS',
    stateName: 'Rio Grande do Sul',
  ),
];
