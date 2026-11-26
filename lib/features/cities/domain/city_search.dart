import 'package:scapematch/features/cities/domain/city.dart';

/// Acima disso o seletor de cidade ganha busca; abaixo, o dropdown curto.
const citySearchThreshold = 12;

const _accentFrom = 'áàâãäåéèêëíìîïóòôõöúùûüçñý';
const _accentTo = 'aaaaaaeeeeiiiiooooouuuucny';

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

/// Busca na lista que o app já tem (cidades com casa ativa), sem acento.
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
    if (!name.contains(folded) && !packed.contains(compact)) {
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
  }
  return [...prefix, ...contains].take(limit).toList(growable: false);
}
