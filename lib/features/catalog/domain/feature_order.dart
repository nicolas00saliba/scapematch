/// Menor destaque vem antes. Sem número, o item fica depois, em ordem de nome.
int compareFeatured(int? aRank, int? bRank, String aName, String bName) {
  if (aRank != null || bRank != null) {
    if (aRank == null) return 1;
    if (bRank == null) return -1;
    final byRank = aRank.compareTo(bRank);
    if (byRank != 0) return byRank;
  }
  return aName.compareTo(bName);
}

/// Coluna ausente ou nula não inventa uma posição.
int? optionalRank(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}
