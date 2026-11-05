import { assert, assertEquals } from "jsr:@std/assert@1";
import { hasRawCardData } from "./raw_card.ts";
import { readCard, tokenizePublicResponse } from "./tokenize_input.ts";

Deno.test("create-charge recusa número, CVV e validade", async () => {
  assertEquals(
    hasRawCardData({
      group_id: "g1",
      billing_type: "PIX",
      idempotency_key: "idem-1234",
      saved_card_id: "card-1",
    }),
    false,
  );
  assertEquals(hasRawCardData({ number: "4111111111111111" }), true);
  assertEquals(hasRawCardData({ card: { ccv: "123" } }), true);
  assertEquals(hasRawCardData({ creditCard: { expiryMonth: "12" } }), true);
  assertEquals(hasRawCardData({ holder: { expiry_year: "2028" } }), true);
  assertEquals(hasRawCardData({ note: "pedido 12 ref 999" }), false);

  const charge = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  assert(charge.includes("hasRawCardData"));
  assert(charge.includes("A cobrança não recebe dados do cartão."));
  assertEquals(charge.includes("tokenizeCreditCard"), false);
  assertEquals(charge.includes("tokenizeCard"), false);
  assertEquals(/console\s*\./.test(charge), false);
  assertEquals(charge.includes("ccv"), false);
  assertEquals(charge.includes("expiryMonth"), false);
});

Deno.test("tokenize-card não loga e a resposta não leva o token", async () => {
  const source = await Deno.readTextFile(
    new URL("../tokenize-card/index.ts", import.meta.url),
  );
  assertEquals(/console\s*\./.test(source), false);
  assert(source.includes("tokenizeCard"));
  assert(source.includes("tokenizePublicResponse"));
  assert(source.includes("corsHeadersFor"));
  assert(source.includes("bindJson"));
  assertEquals(source.includes("error.message"), false);
  assertEquals(
    /JSON\.stringify\(\s*(body|req|text|response)/.test(source),
    false,
  );

  const token = "tok_que_nao_pode_voltar";
  const body = tokenizePublicResponse({
    id: "card-1",
    last4: "4242",
    brand: "VISA",
    creditCardToken: token,
  });
  assertEquals(Object.keys(body).sort(), ["brand", "last4", "saved_card_id"]);
  assertEquals(JSON.stringify(body).includes(token), false);
  assertEquals(readCard({ holder_name: "Ana" }, "127.0.0.1"), null);
  const card = readCard({
    holder_name: "Ana",
    number: "4111111111111111",
    expiry_month: "12",
    expiry_year: "2028",
    ccv: "123",
  }, "203.0.113.4");
  assertEquals(card?.holderName, "Ana");
  assertEquals(card?.remoteIp, "203.0.113.4");
});
