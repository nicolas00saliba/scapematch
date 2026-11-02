/// Faixa de jogadores de uma sala, no texto que o app mostra.
///
/// O mínimo do catálogo fica entre 2 e 6. O máximo é a capacidade.
String playerRangeLabel({required int minimum, required int maximum}) {
  return '$minimum–$maximum jogadores';
}

/// Mínimo sugerido para uma capacidade, sem valores absurdos.
///
/// 2–6, 3–8 e 4–10 são as faixas de exemplo. O mínimo nunca passa de 6.
int suggestedRoomMinimum(int capacity) {
  if (capacity <= 6) {
    return 2;
  }
  if (capacity <= 8) {
    return 3;
  }
  return 4;
}
