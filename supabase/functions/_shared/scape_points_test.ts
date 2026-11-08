import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  accrualIdempotencyKey,
  attributionCovers,
  monthlyReferralCapReached,
  officialHoldDays,
  officialPointValueCents,
  postRewardsOnce,
  quotePointSubsidy,
  quoteReferralRewards,
  referralFraudReason,
  splitMatchesSubsidy,
} from "./scape_points.ts";

const window = {
  startsAt: "2026-01-01T00:00:00.000Z",
  endsAt: "2027-01-01T00:00:00.000Z",
};

Deno.test("C2C de 2,5% vira 250 pontos de 1 centavo", () => {
  assertEquals(officialPointValueCents, 1);
  const lines = quoteReferralRewards({
    grossCents: 10000,
    commissionBps: 2500,
    paidAt: "2026-06-01T00:00:00.000Z",
    playerReferrer: window,
  });
  assertEquals(lines, [{
    program: "c2c",
    cents: 250,
    points: 250,
    payee: "player_points",
  }]);
});

Deno.test("a recompensa não passa da comissão restante", () => {
  const lines = quoteReferralRewards({
    grossCents: 10000,
    commissionBps: 100,
    subsidyCents: 40,
    paidAt: "2026-06-01T00:00:00.000Z",
    playerReferrer: window,
  });
  assertEquals(lines[0].points, 60);
});

Deno.test("jogador e casa dividem a comissão, sem deixar a casa negativa", () => {
  const lines = quoteReferralRewards({
    grossCents: 10000,
    commissionBps: 300,
    paidAt: "2026-06-01T00:00:00.000Z",
    playerReferrer: window,
    venueReferrer: window,
    venueReferrerIsPlayer: true,
  });
  assertEquals(lines.map((line) => line.program), ["c2c", "c2b"]);
  assertEquals(lines[0].points + lines[1].points, 300);
});

Deno.test("fora de um ano, na mesma casa e no primeiro cliente não lança", () => {
  assertEquals(attributionCovers(window, "2027-01-01T00:00:00.000Z"), false);
  assertEquals(
    quoteReferralRewards({
      grossCents: 10000,
      commissionBps: 2500,
      paidAt: "2027-06-01T00:00:00.000Z",
      playerReferrer: window,
    }),
    [],
  );
  assertEquals(
    quoteReferralRewards({
      grossCents: 10000,
      commissionBps: 2500,
      paidAt: "2026-06-01T00:00:00.000Z",
      playerReferrer: window,
      playerReferrerIsVenue: true,
      spendAtReferrerVenue: true,
    }),
    [],
  );
  assertEquals(
    quoteReferralRewards({
      grossCents: 10000,
      commissionBps: 2500,
      paidAt: "2026-06-01T00:00:00.000Z",
      venueReferrer: window,
      payerCustomerRank: 1,
    }),
    [],
  );
  const b2b = quoteReferralRewards({
    grossCents: 10000,
    commissionBps: 2500,
    paidAt: "2026-06-01T00:00:00.000Z",
    venueReferrer: window,
    payerCustomerRank: 2,
  });
  assertEquals(b2b[0].program, "b2b");
  assertEquals(b2b[0].cents, 500);
  assertEquals(b2b[0].payee, "venue_credit");
});

Deno.test("estorno e bloqueio: fraude zera e a chave não duplica", () => {
  assertEquals(
    quoteReferralRewards({
      grossCents: 10000,
      commissionBps: 2500,
      paidAt: "2026-06-01T00:00:00.000Z",
      playerReferrer: window,
      fraudReason: "shared_cpf",
    }),
    [],
  );
  assertEquals(
    referralFraudReason({
      leftCpf: "529.982.247-25",
      rightCpf: "52998224725",
    }),
    "shared_cpf",
  );
  assertEquals(
    referralFraudReason({ leftPhone: "41988880010", rightPhone: "(41) 98888-0010" }),
    "shared_phone",
  );
  assertEquals(referralFraudReason({ sharedCardToken: true }), "shared_card");
  assertEquals(
    referralFraudReason({
      playerCpf: "39053344705",
      venueOwnerCpf: "39053344705",
    }),
    "player_owns_venue",
  );
  const lines = quoteReferralRewards({
    grossCents: 10000,
    commissionBps: 2500,
    paidAt: "2026-06-01T00:00:00.000Z",
    playerReferrer: window,
  });
  const keys = new Set<string>();
  assertEquals(postRewardsOnce(keys, "ch-1", lines).length, 1);
  assertEquals(postRewardsOnce(keys, "ch-1", lines).length, 0);
  assertEquals(accrualIdempotencyKey("ch-1", "c2c"), "accrual:ch-1:c2c");
  assertEquals(monthlyReferralCapReached(20, 20), true);
  assertEquals(officialHoldDays, 30);
});

Deno.test("abatimento muda o percentual e preserva o líquido da casa", () => {
  const quote = quotePointSubsidy({
    grossCents: 10000,
    commissionBps: 2500,
    requestedPoints: 1000,
    availablePoints: 1000,
  });
  assertEquals(quote.houseNetCents, 7500);
  assertEquals(quote.chargedCents, 9000);
  assertEquals(quote.subsidyCents, 1000);
  assertEquals(quote.splitPercent, 83.3334);
  assert(splitMatchesSubsidy(quote.splitPercent ?? 0, 7500, 9000));
  assert((9000 * (quote.splitPercent ?? 0)) / 100 >= 7500);
  const capped = quotePointSubsidy({
    grossCents: 10000,
    commissionBps: 2500,
    requestedPoints: 9000,
    availablePoints: 100,
  });
  assertEquals(capped.points, 100);
  assertEquals(capped.houseNetCents, 7500);
});
