import { assertEquals } from "jsr:@std/assert@1";
import { clientIp } from "./client_ip.ts";
import { readCard } from "./tokenize_input.ts";

Deno.test("o IP vem do header e o remote_ip do body não é usado", () => {
  const forwarded = new Request("https://example.test/tokenize-card", {
    method: "POST",
    headers: { "x-forwarded-for": "203.0.113.9, 10.0.0.1" },
    body: JSON.stringify({ remote_ip: "1.2.3.4", remoteIp: "8.8.8.8" }),
  });
  assertEquals(clientIp(forwarded), "203.0.113.9");

  const cloudflare = new Request("https://example.test/tokenize-card", {
    headers: { "cf-connecting-ip": "198.51.100.7" },
  });
  assertEquals(clientIp(cloudflare), "198.51.100.7");

  const real = new Request("https://example.test/tokenize-card", {
    headers: { "x-real-ip": "192.0.2.8" },
  });
  assertEquals(clientIp(real), "192.0.2.8");

  const prefersForwarded = new Request("https://example.test/tokenize-card", {
    headers: {
      "x-forwarded-for": "203.0.113.9",
      "cf-connecting-ip": "198.51.100.7",
      "x-real-ip": "192.0.2.8",
    },
  });
  assertEquals(clientIp(prefersForwarded), "203.0.113.9");
  assertEquals(clientIp(new Request("https://example.test")), "127.0.0.1");

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
