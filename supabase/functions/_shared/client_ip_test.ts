import { assertEquals } from "jsr:@std/assert@1";
import { clientIp } from "./client_ip.ts";
import { readCard } from "./tokenize_input.ts";

Deno.test("x-real-ip ganha de um X-Forwarded-For forjado", () => {
  const request = new Request("https://example.test/tokenize-card", {
    method: "POST",
    headers: {
      "x-forwarded-for": "1.2.3.4",
      "x-real-ip": "203.0.113.9",
    },
    body: JSON.stringify({ remote_ip: "8.8.8.8", remoteIp: "9.9.9.9" }),
  });
  assertEquals(clientIp(request), "203.0.113.9");
});

Deno.test("só o X-Forwarded-For usa o último IP", () => {
  const request = new Request("https://example.test/tokenize-card", {
    headers: {
      "x-forwarded-for": "1.2.3.4, 198.51.100.20, 203.0.113.50",
    },
  });
  assertEquals(clientIp(request), "203.0.113.50");
});

Deno.test("sem header válido o pedido não leva remoteIp", async () => {
  assertEquals(clientIp(new Request("https://example.test")), null);
  const forgedLast = new Request("https://example.test", {
    headers: { "x-forwarded-for": "1.2.3.4, nao-e-ip" },
  });
  assertEquals(clientIp(forgedLast), null);
  const emptyReal = new Request("https://example.test", {
    headers: {
      "x-real-ip": "999.1.1.1",
      "cf-connecting-ip": "2001:db8::1",
    },
  });
  assertEquals(clientIp(emptyReal), "2001:db8::1");
});

Deno.test("o remote_ip do body não entra no cartão", () => {
  const card = readCard({
    holder_name: "Ana",
    number: "4111111111111111",
    expiry_month: "12",
    expiry_year: "2028",
    ccv: "123",
    remote_ip: "1.2.3.4",
    remoteIp: "8.8.8.8",
  });
  const encoded = JSON.stringify(card);
  assertEquals(encoded.includes("1.2.3.4"), false);
  assertEquals(encoded.includes("8.8.8.8"), false);
  assertEquals(encoded.includes("remote"), false);
});
