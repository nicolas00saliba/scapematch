/// Avaliação de sala. A nota geral é a média das categorias.
/// A nota da casa pondera cada sala pelo número de avaliações.
/// O ranking usa média bayesiana: o prior é a média global.
library;

/// Seis linhas, um toque de 1 a 5 em cada.
enum ReviewCategory {
  story,
  puzzles,
  immersion,
  service,
  comfort,
  value,
}

/// Rótulo da linha, na ordem do formulário.
const reviewCategoryLabels = <ReviewCategory, String>{
  ReviewCategory.story: 'História',
  ReviewCategory.puzzles: 'Enigmas',
  ReviewCategory.immersion: 'Cenário e imersão',
  ReviewCategory.service: 'Atendimento',
  ReviewCategory.comfort: 'Limpeza e conforto',
  ReviewCategory.value: 'Custo-benefício',
};

/// Rótulo do botão. 1 é Horrível e 5 é Incrível.
const reviewScoreLabels = <int, String>{
  1: 'Horrível',
  2: 'Ruim',
  3: 'Regular',
  4: 'Bom',
  5: 'Incrível',
};

/// Comentário opcional. O banco recusa o que passar daqui.
const reviewCommentLimit = 280;

/// Flag, peso do prior e mínimo do ranking. O padrão deixa tudo desligado.
class ReviewSettings {
  const ReviewSettings({
    this.enabled = false,
    this.priorWeight = 10,
    this.rankingMinimum = 10,
  });

  final bool enabled;

  /// m da média bayesiana. O prior pesa como esta quantidade de notas.
  final int priorWeight;

  /// Avaliações para a sala ou a casa entrar no ranking e no JSON-LD.
  final int rankingMinimum;

  static const defaults = ReviewSettings();
}

/// As seis notas de uma avaliação. Cada uma fica entre 1 e 5.
class ReviewScores {
  const ReviewScores({
    required this.story,
    required this.puzzles,
    required this.immersion,
    required this.service,
    required this.comfort,
    required this.value,
  });

  final int story;
  final int puzzles;
  final int immersion;
  final int service;
  final int comfort;
  final int value;

  List<int> get values => [
    story,
    puzzles,
    immersion,
    service,
    comfort,
    value,
  ];

  int scoreOf(ReviewCategory category) {
    return switch (category) {
      ReviewCategory.story => story,
      ReviewCategory.puzzles => puzzles,
      ReviewCategory.immersion => immersion,
      ReviewCategory.service => service,
      ReviewCategory.comfort => comfort,
      ReviewCategory.value => value,
    };
  }

  bool get complete => values.every(scoreInRange);
}

/// 1 a 5, inclusive.
bool scoreInRange(int score) => score >= 1 && score <= 5;

/// Média das seis categorias. Nulo se faltar nota ou se alguma sair de 1 a 5.
double? reviewOverall(ReviewScores scores) {
  if (!scores.complete) return null;
  final sum = scores.values.fold<int>(0, (total, score) => total + score);
  return sum / scores.values.length;
}

/// Comentário curto, sem espaços nas pontas. Vazio é válido.
String normalizeReviewComment(String raw) => raw.trim();

bool reviewCommentTooLong(String raw) =>
    normalizeReviewComment(raw).length > reviewCommentLimit;

enum StarFill { empty, half, full }

/// Cinco estrelas, com meia estrela no 0,5 mais próximo.
List<StarFill> starRow(double average) {
  final clamped = average.clamp(0, 5).toDouble();
  final halves = (clamped * 2).round().clamp(0, 10);
  return [
    for (var index = 0; index < 5; index++)
      if (halves >= (index + 1) * 2)
        StarFill.full
      else if (halves == index * 2 + 1)
        StarFill.half
      else
        StarFill.empty,
  ];
}

/// (C * m + R * n) / (m + n). C é a média global e m é o peso do prior.
double bayesianAverage({
  required double globalMean,
  required int priorWeight,
  required double average,
  required int count,
}) {
  if (priorWeight < 1) {
    throw ArgumentError.value(priorWeight, 'priorWeight', 'm começa em 1');
  }
  if (count < 0) {
    throw ArgumentError.value(count, 'count');
  }
  final weight = priorWeight + count;
  return (globalMean * priorWeight + average * count) / weight;
}

/// A casa é a média das salas, cada uma pesada pela própria quantidade.
double? venueWeightedAverage(Iterable<({double average, int count})> rooms) {
  var weight = 0;
  var sum = 0.0;
  for (final room in rooms) {
    if (room.count <= 0) continue;
    weight += room.count;
    sum += room.average * room.count;
  }
  if (weight == 0) return null;
  return sum / weight;
}

/// Entra no ranking e no JSON-LD só a partir do mínimo configurado.
bool publishesRating({required int count, required int minimum}) {
  if (minimum < 1 || count < 1) return false;
  return count >= minimum;
}

enum CategoryStanding { strength, weakness, even }

/// Acima, abaixo ou na média da cidade, em centésimos.
CategoryStanding standingOf({required double venue, required double city}) {
  final left = (venue * 100).round();
  final right = (city * 100).round();
  if (left > right) return CategoryStanding.strength;
  if (left < right) return CategoryStanding.weakness;
  return CategoryStanding.even;
}

/// Balde de 1 a 5 da nota geral, no inteiro mais próximo.
int distributionBucket(double overall) => overall.round().clamp(1, 5);

/// O convite abre depois da sessão paga e concluída.
/// Dono, sócio e staff são recusados no banco, não aqui.
bool reviewInviteOpen({
  required bool groupCancelled,
  required bool seatActive,
  required bool paid,
  required bool refunded,
  required DateTime endsAt,
  required DateTime now,
}) {
  if (groupCancelled || !seatActive || !paid || refunded) return false;
  return !now.isBefore(endsAt);
}

/// Uma linha do gráfico de meses.
class ReviewMonth {
  const ReviewMonth({
    required this.month,
    required this.count,
    required this.average,
  });

  /// `YYYY-MM` em UTC.
  final String month;
  final int count;
  final double average;
}

/// Comentário público. Só o primeiro nome, sem nota por categoria.
class PublicReviewComment {
  const PublicReviewComment({
    required this.id,
    required this.firstName,
    required this.body,
    required this.overall,
    this.reply,
  });

  final String id;
  final String firstName;
  final String body;
  final double overall;
  final String? reply;
}

/// Agregado que o Parceiro mostra. Sem identidade por categoria.
class VenueReviewBoard {
  const VenueReviewBoard({
    required this.houseName,
    required this.overall,
    required this.count,
    required this.categories,
    required this.cityCategories,
    required this.rooms,
    required this.months,
    required this.distribution,
    required this.comments,
  });

  final String houseName;
  final double overall;
  final int count;
  final Map<ReviewCategory, double> categories;
  final Map<ReviewCategory, double> cityCategories;
  final List<({String name, double average, int count})> rooms;
  final List<ReviewMonth> months;

  /// Quantidade de notas gerais em cada balde de 1 a 5.
  final Map<int, int> distribution;
  final List<PublicReviewComment> comments;
}
