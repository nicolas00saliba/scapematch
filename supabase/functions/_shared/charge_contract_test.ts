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
  assertEquals(charge.includes("remote_ip"), false);
  assert(charge.includes("clientIp"));
  assert(charge.includes("loadOwnedCard"));
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
  assertEquals(source.includes("remote_ip"), false);
  assert(source.includes("clientIp"));
  assert(source.includes("storeSavedCard"));
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
  assertEquals(readCard({ holder_name: "Ana" }), null);
  const card = readCard({
    holder_name: "Ana",
    number: "4111111111111111",
    expiry_month: "12",
    expiry_year: "2028",
    ccv: "123",
    remote_ip: "1.2.3.4",
  });
  assertEquals(card?.holderName, "Ana");
  assertEquals(JSON.stringify(card).includes("1.2.3.4"), false);
  const claimAt = source.indexOf("claim_card_tokenize_attempt");
  const tokenizeAt = source.indexOf("tokenizeCard");
  const customerAt = source.indexOf("customerWithCpf(asaas");
  assert(claimAt > 0 && claimAt < tokenizeAt);
  assert(claimAt < customerAt);
  assert(source.includes("holder_cpf_invalid"));
  assertEquals(source.includes("?? cpf"), false);
  const holderAt = source.indexOf("creditCardHolderInfo");
  const holder = source.slice(holderAt, holderAt + 320);
  assert(holder.includes("card.holderName"));
  assert(holder.includes("holderCpf"));
  assertEquals(/\bcpf\b/.test(holder), false);
  const stored = source.slice(source.indexOf("storeSavedCard(admin"));
  assertEquals(stored.includes("holderCpf"), false);
  assertEquals(stored.includes("cpfCnpj"), false);
  const helper = await Deno.readTextFile(
    new URL("./player_cpf.ts", import.meta.url),
  );
  assert(helper.includes("createCustomer"));
  assert(helper.includes("updateCustomerCpf"));
  assertEquals(/console\s*\./.test(helper), false);
  assert(source.includes("429"));
  assert(source.includes("tokenizeLimitedMessage"));
});
