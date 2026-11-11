import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('a flag nasce desligada, com m e mínimo em 10', () {
    expect(ReviewSettings.defaults.enabled, isFalse);
    expect(ReviewSettings.defaults.priorWeight, 10);
    expect(ReviewSettings.defaults.rankingMinimum, 10);
  });

  test('a nota geral é a média das seis categorias', () {
    const scores = ReviewScores(
      story: 5,
      puzzles: 5,
      immersion: 5,
      service: 4,
      comfort: 4,
      value: 4,
    );
    expect(reviewOverall(scores), 4.5);
    expect(
      reviewOverall(
        const ReviewScores(
          story: 0,
          puzzles: 5,
          immersion: 5,
          service: 5,
          comfort: 5,
          value: 5,
        ),
      ),
      isNull,
    );
  });

  test('estrela arredonda para a meia mais próxima', () {
    expect(starRow(4.5), [
      StarFill.full,
      StarFill.full,
      StarFill.full,
      StarFill.full,
      StarFill.half,
    ]);
    expect(starRow(4.24).where((star) => star == StarFill.full), hasLength(4));
    expect(starRow(4.24), isNot(contains(StarFill.half)));
    expect(starRow(4.25), contains(StarFill.half));
    expect(starRow(5), everyElement(StarFill.full));
    expect(starRow(0.2), contains(StarFill.empty));
  });

  test('bayesiana puxa a nota para a média global', () {
    final score = bayesianAverage(
      globalMean: 3,
      priorWeight: 10,
      average: 5,
      count: 10,
    );
    expect(score, 4);
    expect(
      () => bayesianAverage(
        globalMean: 3,
        priorWeight: 0,
        average: 5,
        count: 10,
      ),
      throwsArgumentError,
    );
  });

  test('a casa pondera a sala pela quantidade de avaliações', () {
    final house = venueWeightedAverage([
      (average: 5, count: 10),
      (average: 1, count: 10),
      (average: 4, count: 0),
    ]);
    expect(house, 3);
    expect(venueWeightedAverage([(average: 5, count: 0)]), isNull);
  });

  test('ranking e JSON-LD exigem o mínimo', () {
    expect(publishesRating(count: 9, minimum: 10), isFalse);
    expect(publishesRating(count: 10, minimum: 10), isTrue);
    expect(publishesRating(count: 10, minimum: 0), isFalse);
  });

  test('ponto forte fica acima da média da cidade', () {
    expect(standingOf(venue: 4.5, city: 4.1), CategoryStanding.strength);
    expect(standingOf(venue: 3.2, city: 4.1), CategoryStanding.weakness);
    expect(standingOf(venue: 4.104, city: 4.1), CategoryStanding.even);
  });

  test('comentário é opcional e curto', () {
    expect(normalizeReviewComment('  '), isEmpty);
    expect(reviewCommentTooLong('a' * reviewCommentLimit), isFalse);
    expect(reviewCommentTooLong('a' * (reviewCommentLimit + 1)), isTrue);
  });

  test('o convite abre só na reserva paga e concluída', () {
    final end = DateTime.utc(2026, 11, 1, 18);
    expect(
      reviewInviteOpen(
        groupCancelled: false,
        seatActive: true,
        paid: true,
        refunded: false,
        endsAt: end,
        now: end,
      ),
      isTrue,
    );
    expect(
      reviewInviteOpen(
        groupCancelled: false,
        seatActive: true,
        paid: true,
        refunded: false,
        endsAt: end,
        now: end.subtract(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(
      reviewInviteOpen(
        groupCancelled: false,
        seatActive: true,
        paid: false,
        refunded: false,
        endsAt: end,
        now: end,
      ),
      isFalse,
    );
    expect(
      reviewInviteOpen(
        groupCancelled: true,
        seatActive: true,
        paid: true,
        refunded: false,
        endsAt: end,
        now: end,
      ),
      isFalse,
    );
    expect(
      reviewInviteOpen(
        groupCancelled: false,
        seatActive: true,
        paid: true,
        refunded: true,
        endsAt: end,
        now: end,
      ),
      isFalse,
    );
  });

  test('as seis categorias têm rótulo de 1 a 5', () {
    expect(reviewCategoryLabels.length, 6);
    expect(reviewScoreLabels[1], 'Horrível');
    expect(reviewScoreLabels[5], 'Incrível');
    expect(distributionBucket(3.5), 4);
    expect(distributionBucket(1.2), 1);
  });
}