import 'package:scapematch/features/cities/domain/city.dart';

part 'municipios_ibge_v1.g.dart';

/// Município do catálogo IBGE usado no cadastro da casa e na busca.
class BrazilianMunicipality {
  const BrazilianMunicipality(
    this.ibge,
    this.id,
    this.name,
    this.stateCode,
    this.stateName,
  );

  final int ibge;
  final String id;
  final String name;
  final String stateCode;
  final String stateName;

  String get label => '$name — $stateCode';

  City toCity() =>
      City(id: id, name: name, stateCode: stateCode, stateName: stateName);
}

class BrazilianState {
  const BrazilianState({required this.code, required this.name});

  final String code;
  final String name;

  String get label => '$code — $name';
}

/// Unidades da Federação, em ordem alfabética da sigla.
const brazilianStates = <BrazilianState>[
  BrazilianState(code: 'AC', name: 'Acre'),
  BrazilianState(code: 'AL', name: 'Alagoas'),
  BrazilianState(code: 'AP', name: 'Amapá'),
  BrazilianState(code: 'AM', name: 'Amazonas'),
  BrazilianState(code: 'BA', name: 'Bahia'),
  BrazilianState(code: 'CE', name: 'Ceará'),
  BrazilianState(code: 'DF', name: 'Distrito Federal'),
  BrazilianState(code: 'ES', name: 'Espírito Santo'),
  BrazilianState(code: 'GO', name: 'Goiás'),
  BrazilianState(code: 'MA', name: 'Maranhão'),
  BrazilianState(code: 'MT', name: 'Mato Grosso'),
  BrazilianState(code: 'MS', name: 'Mato Grosso do Sul'),
  BrazilianState(code: 'MG', name: 'Minas Gerais'),
  BrazilianState(code: 'PA', name: 'Pará'),
  BrazilianState(code: 'PB', name: 'Paraíba'),
  BrazilianState(code: 'PR', name: 'Paraná'),
  BrazilianState(code: 'PE', name: 'Pernambuco'),
  BrazilianState(code: 'PI', name: 'Piauí'),
  BrazilianState(code: 'RJ', name: 'Rio de Janeiro'),
  BrazilianState(code: 'RN', name: 'Rio Grande do Norte'),
  BrazilianState(code: 'RS', name: 'Rio Grande do Sul'),
  BrazilianState(code: 'RO', name: 'Rondônia'),
  BrazilianState(code: 'RR', name: 'Roraima'),
  BrazilianState(code: 'SC', name: 'Santa Catarina'),
  BrazilianState(code: 'SP', name: 'São Paulo'),
  BrazilianState(code: 'SE', name: 'Sergipe'),
  BrazilianState(code: 'TO', name: 'Tocantins'),
];

/// A lista completa cabe no seletor com busca; abaixo disso o app
/// mantém o dropdown curto (as cinco cidades atuais).
const citySearchThreshold = 12;

const _accentFrom = 'áàâãäåéèêëíìîïóòôõöúùûüçñý';
const _accentTo = 'aaaaaaeeeeiiiiooooouuuucny';

final Map<String, BrazilianMunicipality> _byId = {
  for (final city in municipiosIbgeV1) city.id: city,
};

BrazilianMunicipality? municipalityById(String? id) {
  if (id == null || id.isEmpty) {
    return null;
  }
  return _byId[id];
}

/// Remove acentos e pontuação para a busca e a resolução do id.
String foldMunicipalityQuery(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    if (lower == "'" || lower == '’' || lower == '`' || lower == '´') {
      continue;
    }
    final index = _accentFrom.indexOf(lower);
    buffer.write(index >= 0 ? _accentTo[index] : lower);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String compactMunicipalityQuery(String value) {
  return foldMunicipalityQuery(value).replaceAll(' ', '');
}

final Map<String, String> _foldedName = {
  for (final city in municipiosIbgeV1)
    city.id: foldMunicipalityQuery(city.name),
};

final Map<String, String> _compactName = {
  for (final city in municipiosIbgeV1)
    city.id: compactMunicipalityQuery(city.name),
};

List<BrazilianMunicipality> municipalitiesInState(String? stateCode) {
  if (stateCode == null || stateCode.isEmpty) {
    return municipiosIbgeV1;
  }
  final code = stateCode.toUpperCase();
  return [
    for (final city in municipiosIbgeV1)
      if (city.stateCode == code) city,
  ];
}

List<BrazilianMunicipality> searchMunicipalities({
  String? stateCode,
  String query = '',
  int limit = 80,
}) {
  final pool = municipalitiesInState(stateCode);
  final folded = foldMunicipalityQuery(query);
  final compact = compactMunicipalityQuery(query);
  if (folded.isEmpty) {
    return pool.length <= limit ? pool : pool.sublist(0, limit);
  }
  final prefix = <BrazilianMunicipality>[];
  final contains = <BrazilianMunicipality>[];
  for (final city in pool) {
    final name = _foldedName[city.id]!;
    final packed = _compactName[city.id]!;
    final matched =
        name == folded ||
        packed == compact ||
        name.startsWith(folded) ||
        packed.startsWith(compact) ||
        name.contains(folded) ||
        packed.contains(compact);
    if (!matched) {
      continue;
    }
    if (name == folded ||
        packed == compact ||
        name.startsWith(folded) ||
        packed.startsWith(compact)) {
      prefix.add(city);
    } else {
      contains.add(city);
    }
    if (prefix.length + contains.length >= limit * 2) {
      break;
    }
  }
  return [...prefix, ...contains].take(limit).toList(growable: false);
}

List<City> searchCities({
  required List<City> cities,
  String? stateCode,
  String query = '',
  int limit = 80,
}) {
  Iterable<City> pool = cities;
  if (stateCode != null && stateCode.isNotEmpty) {
    final code = stateCode.toUpperCase();
    pool = pool.where((city) => city.stateCode == code);
  }
  final folded = foldMunicipalityQuery(query);
  final compact = compactMunicipalityQuery(query);
  final list = pool.toList(growable: false);
  if (folded.isEmpty) {
    return list.length <= limit ? list : list.sublist(0, limit);
  }
  final prefix = <City>[];
  final contains = <City>[];
  for (final city in list) {
    final name = foldMunicipalityQuery(city.name);
    final packed = compactMunicipalityQuery(city.name);
    final matched = name.contains(folded) || packed.contains(compact);
    if (!matched) {
      continue;
    }
    if (name == folded ||
        packed == compact ||
        name.startsWith(folded) ||
        packed.startsWith(compact)) {
      prefix.add(city);
    } else {
      contains.add(city);
    }
    if (prefix.length + contains.length >= limit * 2) {
      break;
    }
  }
  return [...prefix, ...contains].take(limit).toList(growable: false);
}

final _stateCodes = {for (final state in brazilianStates) state.code};

/// Resolve um id do catálogo a partir do id, do nome ou de "Nome — UF".
/// Nomes repetidos em mais de um estado só resolvem com a UF.
String? resolveMunicipalityId(String input, {String? stateCode}) {
  final raw = input.trim();
  if (raw.isEmpty) {
    return null;
  }
  final lower = raw.toLowerCase();
  final byId = _byId[lower];
  if (byId != null) {
    if (stateCode != null &&
        stateCode.isNotEmpty &&
        byId.stateCode != stateCode.toUpperCase()) {
      return null;
    }
    return byId.id;
  }
  var name = raw;
  var uf = stateCode?.toUpperCase();
  final tokens = foldMunicipalityQuery(raw).split(' ');
  if (tokens.length >= 2 && _stateCodes.contains(tokens.last.toUpperCase())) {
    name = tokens.sublist(0, tokens.length - 1).join(' ');
    uf = tokens.last.toUpperCase();
  }
  final folded = foldMunicipalityQuery(name);
  final compact = compactMunicipalityQuery(name);
  if (folded.isEmpty) {
    return null;
  }
  BrazilianMunicipality? exact;
  var matches = 0;
  for (final city in municipiosIbgeV1) {
    if (uf != null && uf.isNotEmpty && city.stateCode != uf) {
      continue;
    }
    final cityName = _foldedName[city.id]!;
    final packed = _compactName[city.id]!;
    if (cityName == folded || packed == compact) {
      exact = city;
      matches += 1;
      if (matches > 1) {
        return null;
      }
    }
  }
  return exact?.id;
}
