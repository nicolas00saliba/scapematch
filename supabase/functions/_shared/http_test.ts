import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  allowsLocalhostOrigins,
  corsHeadersFor,
  isAllowedOrigin,
  json,
  productionWebOrigin,
} from "./http.ts";

const hosted = { get: () => "https://eujlhicairvksvmssruz.supabase.co" };
const local = { get: () => "http://127.0.0.1:54321" };

function request(origin?: string): Request {
  const headers = new Headers();
  if (origin) headers.set("Origin", origin);
  return new Request("https://example.supabase.co/functions/v1/asaas-webhook", {
    method: "POST",
    headers,
  });
}

Deno.test("o site publicado entra e outro domínio não recebe o curinga", () => {
  assertEquals(isAllowedOrigin(productionWebOrigin, hosted), true);
  assertEquals(isAllowedOrigin("https://evil.example", hosted), false);
  assertEquals(
    isAllowedOrigin("https://nicolas00saliba.github.io.evil.com", hosted),
    false,
  );
  const headers = corsHeadersFor(request(productionWebOrigin), hosted);
  assertEquals(headers["Access-Control-Allow-Origin"], productionWebOrigin);
  assertEquals(
    corsHeadersFor(request("https://evil.example"), hosted)[
      "Access-Control-Allow-Origin"
    ],
    undefined,
  );
  assertEquals(JSON.stringify(headers).includes("*"), false);
});

Deno.test("localhost só é aceito com a função rodando localmente", () => {
  assertEquals(allowsLocalhostOrigins(hosted), false);
  assertEquals(allowsLocalhostOrigins(local), true);
  assertEquals(isAllowedOrigin("http://localhost:8080", hosted), false);
  assertEquals(isAllowedOrigin("http://127.0.0.1:5173", hosted), false);
  assertEquals(isAllowedOrigin("http://localhost:8080", local), true);
  assertEquals(isAllowedOrigin("http://127.0.0.1:5173", local), true);
  assertEquals(isAllowedOrigin("http://localhost.evil.com", local), false);
  const headers = corsHeadersFor(request("http://localhost:8080"), local);
  assertEquals(headers["Access-Control-Allow-Origin"], "http://localhost:8080");
});

Deno.test("pedido sem Origin ainda devolve JSON e não depende de CORS", async () => {
  const response = json({ ok: true }, 200, request(), hosted);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), null);
  assertEquals(await response.json(), { ok: true });
  const webhook = await Deno.readTextFile(
    new URL("../asaas-webhook/index.ts", import.meta.url),
  );
  assertEquals(/origin/i.test(webhook), false);
  assert(webhook.includes("tokensMatch"));
});
