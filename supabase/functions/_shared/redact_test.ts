import { assertEquals } from "jsr:@std/assert@1";
import { redactSensitive, sensitiveStrings } from "./redact.ts";

const pan = "4111111111111111";
const spaced = "4111 1111 1111 1111";
const ccv = "999";
const month = "12";
const year = "2028";

Deno.test("número, CVV, validade e o body mascarado não vazam", () => {
  const body = JSON.stringify({
    card: {
      number: pan,
      ccv,
      expiryMonth: month,
      expiryYear: year,
    },
  });
  const leaked = [
    `Asaas 400: cartão ${pan} ccv ${ccv} validade ${month}/${year}`,
    `número espaçado ${spaced}`,
    body,
  ].join("\n");
  const secrets = sensitiveStrings(JSON.parse(body));
  const redacted = redactSensitive(leaked, secrets);
  assertEquals(redacted.includes(pan), false);
  assertEquals(redacted.includes(spaced), false);
  assertEquals(redacted.includes(ccv), false);
  assertEquals(redacted.includes(`${month}/${year}`), false);
  assertEquals(redacted.includes(`"number":"${pan}"`), false);
  assertEquals(redacted.includes(`"ccv":"${ccv}"`), false);
  assertEquals(redacted.includes("[redacted]"), true);
});
