enum Difficulty { easy, medium, hard }

extension DifficultyText on Difficulty {
  String get labelPt {
    return switch (this) {
      Difficulty.easy => 'Fácil',
      Difficulty.medium => 'Médio',
      Difficulty.hard => 'Difícil',
    };
  }
}
