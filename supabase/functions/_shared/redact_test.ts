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

Deno.test("mascara creditCardToken aninhado e na mensagem de erro", () => {
  const camel = "tok_camel_secret_value";
  const snake = "tok_snake_secret_value";
  const upper = "tok_upper_secret_value";
  const echoed = "tok_echoed_in_error_body";
  const nested = JSON.stringify({
    errors: [{
      description: "falhou",
      details: {
        creditCardToken: camel,
        credit_card_token: snake,
        CREDIT_CARD_TOKEN: upper,
      },
    }],
  });
  const message = [
    `Asaas 400: ${JSON.stringify({
      errors: [{
        code: "invalid_object",
        description: `creditCardToken=${echoed} rejeitado`,
        credit_card_token: echoed,
      }],
    })}`,
    "o campo creditCardToken é obrigatório",
    "pedido 12 ref 999 vence 2026-11-12",
  ].join("\n");
  const redacted = redactSensitive(`${nested}\n${message}`);
  assertEquals(redacted.includes(camel), false);
  assertEquals(redacted.includes(snake), false);
  assertEquals(redacted.includes(upper), false);
  assertEquals(redacted.includes(echoed), false);
  assertEquals(redacted.includes('"creditCardToken":"[redacted]"'), true);
  assertEquals(redacted.includes('"credit_card_token":"[redacted]"'), true);
  assertEquals(redacted.includes('"CREDIT_CARD_TOKEN":"[redacted]"'), true);
  assertEquals(redacted.includes("creditCardToken=[redacted]"), true);
  assertEquals(redacted.includes("Asaas 400"), true);
  assertEquals(redacted.includes("o campo creditCardToken é obrigatório"), true);
  assertEquals(redacted.includes("pedido 12"), true);
  assertEquals(redacted.includes("ref 999"), true);
  assertEquals(redacted.includes("2026-11-12"), true);
});

Deno.test("mascara os campos do titular e preserva a palavra solta", () => {
  const holder = {
    name: "Ana Silva",
    email: "ana.titular@example.com",
    phone: "1133334444",
    mobilePhone: "11987654321",
    postalCode: "01310100",
    addressNumber: "1000",
    addressComplement: "sala 2",
    postal_code: "04567000",
    address_number: "42",
  };
  const body = JSON.stringify({ creditCardHolderInfo: holder });
  const labeled = "Asaas 400: email=ana.titular@example.com rejeitado";
  const redacted = redactSensitive(
    `${body}\n${labeled}\no campo name é obrigatório\npedido 12 ref 999`,
  );
  for (const value of Object.values(holder)) {
    assertEquals(redacted.includes(value), false);
  }
  assertEquals(redacted.includes("ana.titular@example.com"), false);
  assertEquals(redacted.includes('"name":"[redacted]"'), true);
  assertEquals(redacted.includes('"email":"[redacted]"'), true);
  assertEquals(redacted.includes('"phone":"[redacted]"'), true);
  assertEquals(redacted.includes('"mobilePhone":"[redacted]"'), true);
  assertEquals(redacted.includes('"postalCode":"[redacted]"'), true);
  assertEquals(redacted.includes('"addressNumber":"[redacted]"'), true);
  assertEquals(redacted.includes('"addressComplement":"[redacted]"'), true);
  assertEquals(redacted.includes('"postal_code":"[redacted]"'), true);
  assertEquals(redacted.includes("email=[redacted]"), true);
  assertEquals(redacted.includes("o campo name é obrigatório"), true);
  assertEquals(redacted.includes("pedido 12"), true);
  assertEquals(redacted.includes("ref 999"), true);
  assertEquals(redacted.includes("Asaas 400"), true);
});
