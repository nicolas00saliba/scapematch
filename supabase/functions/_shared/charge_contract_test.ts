import { assert, assertEquals } from "jsr:@std/assert@1";
import { hasRawCardData } from "./raw_card.ts";
import { readCard, tokenizePublicResponse } from "./tokenize_input.ts";

Deno.test("create-charge recusa número, CVV e validade", async () => {
  assertEquals(hasRawCardData({ number: "4111111111111111" }), true);
  assertEquals(hasRawCardData({ group_id: "g1" }), false);
  const charge = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  assert(charge.includes("hasRawCardData"));
  assert(charge.includes("A cobrança não recebe dados do cartão."));
  assertEquals(charge.includes("tokenizeCreditCard"), false);
  assertEquals(charge.includes("AsaasProvider"), false);
  assertEquals(/console\s*\./.test(charge), false);
  assert(charge.includes("createAlternateCharge"));
  assert(charge.includes("isHistoricalAsaas"));
});

Deno.test("tokenize-card não recebe o número", async () => {
  const source = await Deno.readTextFile(
    new URL("../tokenize-card/index.ts", import.meta.url),
  );
  assertEquals(/console\s*\./.test(source), false);
  assert(source.includes("hasRawCardData"));
  assert(source.includes("O número do cartão não passa pelo servidor."));
  assertEquals(source.includes("tokenizeCard"), false);
  const token = "tok_que_nao_pode_voltar";
  const body = tokenizePublicResponse({
    id: "card-1",
    last4: "4242",
    brand: "VISA",
    creditCardToken: token,
  });
  assertEquals(JSON.stringify(body).includes(token), false);
  const card = readCard({
    holder_name: "Ana",
    number: "4111111111111111",
    expiry_month: "12",
    expiry_year: "2028",
    ccv: "123",
    remote_ip: "1.2.3.4",
  });
  assertEquals(JSON.stringify(card).includes("1.2.3.4"), false);
});
