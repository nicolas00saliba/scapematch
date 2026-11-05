import { assertEquals } from "jsr:@std/assert@1";
import { gateTokenize } from "./tokenize_limit.ts";

Deno.test("o 6º cartão não segue para o Asaas", async () => {
  const activeCards = 5;
  let tokenized = 0;
  const decision = await gateTokenize(
    () => Promise.resolve(activeCards < 5),
    () => {
      tokenized += 1;
      return Promise.resolve();
    },
  );
  assertEquals(decision, "limited");
  assertEquals(tokenized, 0);
});

Deno.test("a 6ª tentativa na hora não segue para o Asaas", async () => {
  let attempts = 0;
  let tokenized = 0;
  const claim = () => {
    attempts += 1;
    return Promise.resolve(attempts <= 5);
  };
  for (let n = 0; n < 5; n++) {
    assertEquals(
      await gateTokenize(claim, () => {
        tokenized += 1;
        return Promise.resolve();
      }),
      "ok",
    );
  }
  assertEquals(
    await gateTokenize(claim, () => {
      tokenized += 1;
      return Promise.resolve();
    }),
    "limited",
  );
  assertEquals(attempts, 6);
  assertEquals(tokenized, 5);
});
