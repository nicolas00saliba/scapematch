import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  final paidAt = DateTime.utc(2026, 6, 1);
  final window = AttributionSlice(
    startsAt: DateTime.utc(2026, 1, 1),
    endsAt: attributionEndsAt(DateTime.utc(2026, 1, 1), 365),
  );

  SpendRewardInput spend({
    int grossCents = 10000,
    int commissionBps = 2500,
    int subsidyCents = 0,
    int firstBookingDiscountCents = 0,
    AttributionSlice? playerReferrer,
    bool playerReferrerIsVenue = false,
    bool spendAtReferrerVenue = false,
    AttributionSlice? venueReferrer,
    bool venueReferrerIsPlayer = false,
    bool payerCpfMissing = false,
    bool playerReferrerCpfMissing = false,
    bool venueReferrerCpfMissing = false,
    String? fraudReason,
    bool playerPayerIsReferrer = false,
    bool venuePayerIsReferrer = false,
    int payerRewardedAccounts = 0,
    bool playerSubjectAlreadyRewarded = false,
    int playerDeviceCluster = 0,
    DateTime? at,
  }) {
    return SpendRewardInput(
      grossCents: grossCents,
      commissionBps: commissionBps,
      subsidyCents: subsidyCents,
      firstBookingDiscountCents: firstBookingDiscountCents,
      paidAt: at ?? paidAt,
      playerReferrer: playerReferrer,
      playerReferrerIsVenue: playerReferrerIsVenue,
      spendAtReferrerVenue: spendAtReferrerVenue,
      venueReferrer: venueReferrer,
      venueReferrerIsPlayer: venueReferrerIsPlayer,
      payerCpfMissing: payerCpfMissing,
      playerReferrerCpfMissing: playerReferrerCpfMissing,
      venueReferrerCpfMissing: venueReferrerCpfMissing,
      fraudReason: fraudReason,
      playerPayerIsReferrer: playerPayerIsReferrer,
      venuePayerIsReferrer: venuePayerIsReferrer,
      payerRewardedAccounts: payerRewardedAccounts,
      playerSubjectAlreadyRewarded: playerSubjectAlreadyRewarded,
      playerDeviceCluster: playerDeviceCluster,
    );
  }

  test('1 ponto vale 1 centavo e o C2C fica em 2,5%', () {
    expect(ReferralRates.official.pointValueCents, 1);
    expect(ReferralRates.official.c2cBps, 250);
    expect(ReferralRates.official.cashbackBps, 100);
    final lines = quoteReferralRewards(spend(playerReferrer: window));
    expect(lines.map((line) => line.program), ['cashback', 'c2c']);
    expect(lines.first.points, 100);
    expect(lines.last.points, 250);
    expect(lines.last.cents, 250);
    expect(lines.last.payee, RewardPayee.playerPoints);
  });

  test('a recompensa não passa da comissão que sobrou', () {
    final lines = quoteReferralRewards(
      spend(playerReferrer: window, commissionBps: 100, subsidyCents: 40),
    );
    expect(lines.single.program, 'cashback');
    expect(lines.single.points, 60);
    expect(lines.single.cents, 60);
  });

  test('jogador e casa dividem a mesma comissão, o jogador primeiro', () {
    final lines = quoteReferralRewards(
      spend(
        playerReferrer: window,
        venueReferrer: window,
        venueReferrerIsPlayer: true,
        commissionBps: 300,
      ),
    );
    expect(lines.map((line) => line.program), ['cashback', 'c2c']);
    expect(lines[0].points, 100);
    expect(lines[1].points, 200);
    expect(lines[0].cents + lines[1].cents, 300);
  });

  test('fora da janela de um ano não lança', () {
    final expired = AttributionSlice(
      startsAt: DateTime.utc(2025, 1, 1),
      endsAt: attributionEndsAt(DateTime.utc(2025, 1, 1), 365),
    );
    final expiredLines = quoteReferralRewards(spend(playerReferrer: expired));
    expect(expiredLines.map((line) => line.program), ['cashback']);
    expect(expiredLines.single.points, 100);
    expect(attributionCovers(window, window.endsAt), isFalse);
  });

  test('B2C só vale em outra casa e vira crédito, não ponto', () {
    expect(
      quoteReferralRewards(
        spend(
          playerReferrer: window,
          playerReferrerIsVenue: true,
          spendAtReferrerVenue: true,
        ),
      ).map((line) => line.program),
      ['cashback'],
    );
    final lines = quoteReferralRewards(
      spend(playerReferrer: window, playerReferrerIsVenue: true),
    );
    final credit = lines.singleWhere((line) => line.program == 'b2c');
    expect(lines.first.program, 'cashback');
    expect(credit.payee, RewardPayee.venueCredit);
    expect(credit.points, 0);
    expect(credit.cents, 250);
  });

  test('B2B é 5% em toda reserva do ano, menos a do desconto de 20%', () {
    expect(
      quoteReferralRewards(
        spend(venueReferrer: window, firstBookingDiscountCents: 2000),
      ).map((line) => line.program),
      ['cashback'],
    );
    final firstVisit = quoteReferralRewards(spend(venueReferrer: window));
    final nextVisit = quoteReferralRewards(spend(venueReferrer: window));
    final firstCredit = firstVisit.singleWhere((line) => line.program == 'b2b');
    final nextCredit = nextVisit.singleWhere((line) => line.program == 'b2b');
    expect(firstVisit.first.program, 'cashback');
    expect(firstCredit.cents, 500);
    expect(nextCredit.cents, 500);
    expect(firstCredit.payee, RewardPayee.venueCredit);
  });

  test('C2B paga o jogador que indicou a casa', () {
    final lines = quoteReferralRewards(
      spend(venueReferrer: window, venueReferrerIsPlayer: true),
    );
    expect(lines.map((line) => line.program), ['cashback', 'c2b']);
    expect(lines.last.points, 250);
  });

  test('CPF ausente segura o ponto e a fraude zera o lançamento', () {
    expect(
      quoteReferralRewards(spend(playerReferrer: window, payerCpfMissing: true))
          .map((line) => line.program),
      ['cashback'],
    );
    expect(
      quoteReferralRewards(
        spend(playerReferrer: window, fraudReason: 'shared_cpf'),
      ).map((line) => line.program),
      ['cashback'],
    );
    final alone = quoteReferralRewards(spend());
    expect(alone.single.program, 'cashback');
    expect(alone.single.points, 100);
  });

  test('antifraude compara documento, telefone, cartão e dono da casa', () {
    expect(
      referralFraudReason(leftCpf: '529.982.247-25', rightCpf: '52998224725'),
      'shared_cpf',
    );
    expect(
      referralFraudReason(
        leftPhone: '(41) 98888-0010',
        rightPhone: '41988880010',
      ),
      'shared_phone',
    );
    expect(referralFraudReason(sharedCardToken: true), 'shared_card');
    expect(
      referralFraudReason(
        playerCpf: '39053344705',
        venueDocument: '390.533.447-05',
      ),
      'player_owns_venue',
    );
    expect(
      referralFraudReason(
        playerCpf: '52998224725',
        venueOwnerCpf: '52998224725',
      ),
      'player_owns_venue',
    );
    expect(
      referralFraudReason(leftCpf: '52998224725', rightCpf: '39053344705'),
      isNull,
    );
  });

  test('repetir o lançamento não duplica a chave', () {
    final lines = quoteReferralRewards(spend(playerReferrer: window));
    final keys = <String>{};
    final first = postRewardsOnce(
      existingKeys: keys,
      chargeId: 'ch-1',
      lines: lines,
    );
    final second = postRewardsOnce(
      existingKeys: keys,
      chargeId: 'ch-1',
      lines: lines,
    );
    expect(first, hasLength(2));
    expect(second, isEmpty);
    expect(accrualIdempotencyKey('ch-1', 'c2c'), 'accrual:ch-1:c2c');
  });

  test('o abatimento cobra menos e o split devolve o líquido cheio', () {
    final quote = quotePointSubsidy(
      grossCents: 10000,
      commissionBps: 2500,
      requestedPoints: 1000,
      availablePoints: 1000,
    );
    expect(quote.commissionCents, 2500);
    expect(quote.houseNetCents, 7500);
    expect(quote.subsidyCents, 1000);
    expect(quote.chargedCents, 9000);
    expect(quote.points, 1000);
    expect(quote.splitPercent, 83.3334);
    final returned = quote.chargedCents * quote.splitPercent! / 100;
    expect(returned, greaterThanOrEqualTo(quote.houseNetCents));
  });

  test('o ponto não come o líquido da casa nem passa do saldo', () {
    final quote = quotePointSubsidy(
      grossCents: 10000,
      commissionBps: 2500,
      requestedPoints: 9000,
      availablePoints: 100,
    );
    expect(quote.points, 100);
    expect(quote.chargedCents, 9900);
    expect(quote.houseNetCents, 7500);
    expect(quote.maxPoints, 2500);
  });

  test('carência de 30 dias e desconto só com o CPF de quem pagou', () {
    expect(
      pointsAvailableAt(DateTime.utc(2026, 6, 1), 30),
      DateTime.utc(2026, 7, 1),
    );
    expect(
      firstBookingDiscountCents(
        grossCents: 10000,
        discountBps: 2000,
        commissionCentsValue: 1500,
      ),
      1500,
    );
    expect(
      payerDocumentStatus(
        accountCpf: '529.982.247-25',
        payerDocument: '52998224725',
      ),
      'matched',
    );
    expect(
      payerDocumentStatus(
        accountCpf: '52998224725',
        payerDocument: '39053344705',
      ),
      'mismatch',
    );
    expect(
      payerDocumentStatus(
        accountCpf: '52998224725',
        payerDocument: '***.456.789-**',
      ),
      'unverified',
    );
    expect(
      payerDocumentStatus(accountCpf: '52998224725', payerDocument: null),
      'unverified',
    );
    expect(referralBenefitAllowed('matched'), isTrue);
    expect(referralBenefitAllowed('mismatch'), isTrue);
    expect(referralBenefitAllowed('unverified'), isTrue);
    expect(
      gatedFirstBookingDiscountCents(
        payerStatus: 'mismatch',
        grossCents: 10000,
        discountBps: 2000,
        commissionCentsValue: 2500,
      ),
      2000,
    );
    expect(
      gatedFirstBookingDiscountCents(
        payerStatus: 'unverified',
        grossCents: 10000,
        discountBps: 2000,
        commissionCentsValue: 2500,
      ),
      2000,
    );
    expect(
      gatedFirstBookingDiscountCents(
        payerStatus: 'matched',
        grossCents: 10000,
        discountBps: 2000,
        commissionCentsValue: 2500,
      ),
      2000,
    );
  });

  test('ponto que não fecha em centavos inteiros não vira fração', () {
    const rates = ReferralRates(pointValueCents: 3);
    final lines = quoteReferralRewards(
      spend(
        grossCents: 40,
        commissionBps: 10000,
        playerReferrer: window,
        venueReferrer: window,
      ),
      rates: rates,
    );
    expect(lines.map((line) => line.program), ['b2b']);
    expect(lines.single.cents, 2);
  });

  test('pagador indicador, teto de 3 contas e aparelho repetido', () {
    final self = quoteReferralRewards(
      spend(playerReferrer: window, playerPayerIsReferrer: true),
    );
    expect(self.map((line) => line.program), ['cashback']);

    final fourth = quoteReferralRewards(
      spend(playerReferrer: window, payerRewardedAccounts: 3),
    );
    expect(fourth.map((line) => line.program), ['cashback']);

    final again = quoteReferralRewards(
      spend(
        playerReferrer: window,
        payerRewardedAccounts: 3,
        playerSubjectAlreadyRewarded: true,
      ),
    );
    expect(again.map((line) => line.program), ['cashback', 'c2c']);

    final review = quoteReferralRewards(
      spend(playerReferrer: window, playerDeviceCluster: 2),
    );
    expect(review.last.program, 'c2c');
    expect(review.last.reviewStatus, 'em_revisao');
    expect(review.first.reviewStatus, isNull);

    expect(ReferralRates.official.payerReferredAccountCap, 3);
    expect(ReferralRates.official.sameDeviceReviewThreshold, 2);
  });
}
