import { assertEquals } from "jsr:@std/assert@1";
import { cardKey, documentHash } from "./payer_identity.ts";

Deno.test("hash do documento coincide com o SHA-256 do SQL", async () => {
  assertEquals(
    await documentHash("529.982.247-25"),
    "7281dfb5e8becca0a1c5e77c1268baacb0f983572b8c204fd8df72b24175b231",
  );
  assertEquals(await documentHash("***.456.789-**"), null);
  assertEquals(cardKey("VISA", "8829"), "visa:8829");
  assertEquals(cardKey("", "8829"), null);
});
