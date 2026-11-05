import { assertEquals } from "jsr:@std/assert@1";
import { redactSensitive } from "./redact.ts";

const pan = "4111111111111111";
const spaced = "4111 1111 1111 1111";

Deno.test("mascara PAN e campos nomeados e preserva números curtos", () => {
  const body = JSON.stringify({
    card: {
      number: pan,
      ccv: "999",
      expiryMonth: "12",
      expiryYear: "2028",
    },
    note: "pedido 12 ref 999 vence 2026-11-12",
  });
  const leaked = [
    `Asaas 400: cartão ${pan} e ${spaced}`,
    body,
  ].join("\n");
  const redacted = redactSensitive(leaked);
  assertEquals(redacted.includes(pan), false);
  assertEquals(redacted.includes(spaced), false);
  assertEquals(redacted.includes('"number":"[redacted]"'), true);
  assertEquals(redacted.includes('"ccv":"[redacted]"'), true);
  assertEquals(redacted.includes('"expiryMonth":"[redacted]"'), true);
  assertEquals(redacted.includes('"expiryYear":"[redacted]"'), true);
  assertEquals(redacted.includes("pedido 12"), true);
  assertEquals(redacted.includes("ref 999"), true);
  assertEquals(redacted.includes("2026-11-12"), true);
  assertEquals(redacted.includes("Asaas 400"), true);
});
