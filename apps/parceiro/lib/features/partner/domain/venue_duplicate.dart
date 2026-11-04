// Normalização e comparação de casas. Espelha a migration
// 20261104130000_venue_duplicates: só dígitos no documento, nome sem
// acento e sem sufixo, e a similaridade de trigrama do pg_trgm.

const venueCities = <(String id, String name)>[
  ('curitiba', 'Curitiba'),
  ('sao-paulo', 'São Paulo'),
  ('rio-de-janeiro', 'Rio de Janeiro'),
  ('belo-horizonte', 'Belo Horizonte'),
  ('porto-alegre', 'Porto Alegre'),
];

const venueConflictDocument = 'documento';
const venueConflictAddress = 'endereço';
const venueConflictName = 'nome parecido';

const venueNameSimilarity = 0.5;

/// Quem ainda não tem casa e abre o cadastro de exemplo.
const venueSignupOwnerId = 'owner-signup';

String? normalizeDocument(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  return digits;
}

String normalizeAddressNumber(String value) {
  final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (cleaned.isEmpty ||
      cleaned == 'sn' ||
      cleaned == 'snum' ||
      cleaned == 'semnumero') {
    return 'sn';
  }
  final digits = cleaned.replaceFirst(RegExp(r'^[a-z]+'), '');
  if (digits.isEmpty) {
    return 'sn';
  }
  return digits;
}

String normalizePostalCode(String value) {
  return value.replaceAll(RegExp(r'\D'), '');
}

String unaccent(String value) {
  const from = 'áàâãäåéèêëíìîïóòôõöúùûüçñý';
  const to = 'aaaaaaeeeeiiiiooooouuuucny';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    final index = from.indexOf(lower);
    if (index >= 0) {
      buffer.write(char == lower ? to[index] : to[index].toUpperCase());
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

String normalizeVenueName(String name) {
  var value = unaccent(name).toLowerCase();
  value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  value = value.replaceAll(
    RegExp(r'\b(escape rooms|escape room|sala de escape|casa de escape)\b'),
    ' ',
  );
  value = value.replaceAll(RegExp(r'\bs a\b'), ' ');
  value = value.replaceAll(
    RegExp(
      r'\b(ltda|limitada|eireli|epp|me|sa|sociedade|anonima|escape|room|rooms)\b',
    ),
    ' ',
  );
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? resolveVenueCity(String input) {
  final raw = input.trim().toLowerCase();
  if (raw.isEmpty) {
    return null;
  }
  for (final city in venueCities) {
    if (city.$1 == raw) {
      return city.$1;
    }
  }
  final folded = unaccent(raw).toLowerCase();
  for (final city in venueCities) {
    if (unaccent(city.$2).toLowerCase() == folded) {
      return city.$1;
    }
  }
  return null;
}

String venueCityLabel(String cityId) {
  for (final city in venueCities) {
    if (city.$1 == cityId) {
      return city.$2;
    }
  }
  return cityId;
}

double trigramSimilarity(String left, String right) {
  final a = _trigrams(left);
  final b = _trigrams(right);
  if (a.isEmpty && b.isEmpty) {
    return 1;
  }
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  var shared = 0;
  for (final gram in a) {
    if (b.contains(gram)) {
      shared++;
    }
  }
  return shared / (a.length + b.length - shared);
}

Set<String> _trigrams(String value) {
  final padded = '  $value ';
  final grams = <String>{};
  for (var i = 0; i + 3 <= padded.length; i++) {
    grams.add(padded.substring(i, i + 3));
  }
  return grams;
}

bool venueNamesMatch(String left, String right) {
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (left == right) {
    return true;
  }
  if (_containsWord(left, right) || _containsWord(right, left)) {
    return true;
  }
  return left.length >= 4 &&
      right.length >= 4 &&
      trigramSimilarity(left, right) >= venueNameSimilarity;
}

bool _containsWord(String haystack, String needle) {
  if (needle.length < 4) {
    return false;
  }
  return haystack.startsWith('$needle ') ||
      haystack.endsWith(' $needle') ||
      haystack.contains(' $needle ');
}

String formatVenueDocument(String digits) {
  if (digits.length == 14) {
    return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
  }
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
  }
  return digits;
}
