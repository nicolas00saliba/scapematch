import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  buyerInterestFromQuote,
  chargeAmountBody,
  commissionCents,
  fixedSplit,
  groupPaymentAction,
  holdUntilGroupConfirms,
  installmentCharge,
  pagbankSplitBody,
  venueShareCents,
} from "./pagbank_rules.ts";

Deno.test("a casa leva a parte exata do bruto e a taxa não entra nela", () => {
  const gross = 10_000;
  const bps = 2500;
  const venue = venueShareCents(gross, bps);
  assertEquals(commissionCents(gross, bps), 2500);
  assertEquals(venue, 7500);
  const split = fixedSplit({
    chargedCents: gross,
    venueCents: venue,
    venueAccountId: "ACCO_VENUE",
    primaryAccountId: "ACCO_PRIMARY",
  });
  assertEquals(split.venueCents, 7500);
  assertEquals(split.primaryCents, 2500);
  assertEquals(split.feePayer, "primary");
  assertEquals(
    split.receivers.reduce((sum, item) => sum + item.amountCents, 0),
    gross,
  );
  const body = pagbankSplitBody(split);
  const receivers = body.receivers as Record<string, unknown>[];
  const house = receivers[0];
  assertEquals((house.amount as { value: number }).value, 7500);
  assertEquals(
    (house.configurations as { custody: { apply: boolean } }).custody.apply,
    true,
  );
  assertEquals(JSON.stringify(house).includes("fee"), false);
  const primary = receivers[1];
  assertEquals((primary.amount as { value: number }).value, 2500);
});

Deno.test("comissão menor que uma taxa hipotética não reduz a casa", () => {
  const gross = 1_500;
  const venue = venueShareCents(gross, 1000);
  assertEquals(venue, 1350);
  const split = fixedSplit({
    chargedCents: gross,
    venueCents: venue,
    venueAccountId: "ACCO_VENUE",
    primaryAccountId: "ACCO_PRIMARY",
  });
  assertEquals(split.venueCents, 1350);
  assertEquals(split.primaryCents, 150);
});

Deno.test("3x não manda juro do comprador; 4x soma o juro cotado", () => {
  const free = installmentCharge({
    principalCents: 20_000,
    installments: 3,
    buyerInterestCents: 900,
  });
  assertEquals(free.merchantAbsorbsInterest, true);
  assertEquals(free.amountCents, 20_000);
  assertEquals(free.buyerInterestCents, 0);
  assertEquals(chargeAmountBody(free).fees, undefined);

  const paid = installmentCharge({
    principalCents: 20_000,
    installments: 4,
    buyerInterestCents: 640,
  });
  assertEquals(paid.merchantAbsorbsInterest, false);
  assertEquals(paid.amountCents, 20_640);
  const amount = chargeAmountBody(paid);
  assertEquals(amount.value, 20_640);
  assertEquals(
    (amount.fees as { buyer: { interest: { total: number; installments: number } } })
      .buyer.interest,
    { total: 640, installments: 1 },
  );
});

Deno.test("abaixo de R$ 150 só cabe 1x", () => {
  assertEquals(
    installmentCharge({ principalCents: 14_999, installments: 1 }).installments,
    1,
  );
  assertThrows(
    () => installmentCharge({ principalCents: 14_999, installments: 2 }),
    Error,
    "parcelas",
  );
  assertThrows(
    () => installmentCharge({ principalCents: 20_000, installments: 13 }),
    Error,
    "parcelas",
  );
});

Deno.test("confirmação solta a custódia; sem confirmação estorna Pix e não captura cartão", () => {
  assertEquals(
    groupPaymentAction({
      confirmed: true,
      billingType: "PIX",
      status: "paid",
    }),
    "release_custody",
  );
  assertEquals(
    groupPaymentAction({
      confirmed: true,
      billingType: "CREDIT_CARD",
      status: "authorized",
    }),
    "release_custody",
  );
  assertEquals(
    groupPaymentAction({
      confirmed: false,
      billingType: "PIX",
      status: "paid",
    }),
    "refund_pix",
  );
  assertEquals(
    groupPaymentAction({
      confirmed: false,
      billingType: "CREDIT_CARD",
      status: "authorized",
    }),
    "void_card",
  );
  assertEquals(
    groupPaymentAction({
      confirmed: false,
      billingType: "PIX",
      status: "pending",
    }),
    "cancel_pending_pix",
  );
  assertEquals(
    holdUntilGroupConfirms,
    "O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.",
  );
  assertEquals(
    holdUntilGroupConfirms,
    "O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.",
  );
});

Deno.test("a cotação de juros lê o total do comprador no plano de 4x", () => {
  const quote = {
    payment_methods: {
      credit_card: {
        mastercard: {
          installment_plans: [
            {
              installments: 3,
              interest_free: true,
              amount: { value: 20000 },
            },
            {
              installments: 4,
              interest_free: false,
              amount: {
                value: 20640,
                fees: { buyer: { interest: { total: 640, installments: 1 } } },
              },
            },
          ],
        },
      },
    },
  };
  assertEquals(buyerInterestFromQuote(quote, 3), 0);
  assertEquals(buyerInterestFromQuote(quote, 4), 640);
  assertEquals(buyerInterestFromQuote(quote, 9), null);
});
