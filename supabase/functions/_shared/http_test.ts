import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  allowsLocalhostOrigins,
  corsHeadersFor,
  isAllowedOrigin,
  json,
  productionWebOrigin,
  productionWebOrigins,
} from "./http.ts";

function envOf(values: Record<string, string>): { get(name: string): string | undefined } {
  return { get: (name) => values[name] };
}

const hosted = envOf({
  SUPABASE_URL: "https://eujlhicairvksvmssruz.supabase.co",
});
const local = envOf({ SUPABASE_URL: "http://127.0.0.1:54321" });

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

Deno.test("ALLOWED_ORIGINS troca a lista e o curinga não passa", () => {
  const custom = envOf({
    SUPABASE_URL: "https://eujlhicairvksvmssruz.supabase.co",
    ALLOWED_ORIGINS: "https://app.example, https://nicolas00saliba.github.io",
  });
  assertEquals(isAllowedOrigin("https://app.example", custom), true);
  assertEquals(isAllowedOrigin(productionWebOrigin, custom), true);
  assertEquals(isAllowedOrigin("https://evil.example", custom), false);
  const star = envOf({
    SUPABASE_URL: "https://eujlhicairvksvmssruz.supabase.co",
    ALLOWED_ORIGINS: "*",
  });
  assertEquals(isAllowedOrigin("https://evil.example", star), false);
  assertEquals(isAllowedOrigin(productionWebOrigin, star), false);
  assertEquals(JSON.stringify(corsHeadersFor(request("https://evil.example"), star)).includes("*"), false);
});

Deno.test("os subdomínios próprios entram no padrão sem ALLOWED_ORIGINS", () => {
  const listed = (origin: string) =>
    productionWebOrigins.some((item) => item === origin);
  assertEquals(listed(productionWebOrigin), true);
  assertEquals(listed("https://app.scapematch.com.br"), true);
  assertEquals(listed("https://parceiro.scapematch.com.br"), true);
  assertEquals(listed("https://demo.scapematch.com.br"), true);
  assertEquals(listed("https://parceiro-demo.scapematch.com.br"), true);
  assertEquals(isAllowedOrigin("https://app.scapematch.com.br", hosted), true);
  assertEquals(isAllowedOrigin("https://parceiro.scapematch.com.br", hosted), true);
  assertEquals(isAllowedOrigin("https://demo.scapematch.com.br", hosted), true);
  assertEquals(
    isAllowedOrigin("https://parceiro-demo.scapematch.com.br", hosted),
    true,
  );
  assertEquals(isAllowedOrigin("https://scapematch.com.br", hosted), true);
});
