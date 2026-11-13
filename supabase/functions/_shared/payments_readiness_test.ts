import { assert, assertEquals } from "jsr:@std/assert";
import { asaasProductionBaseUrl, asaasSandboxBaseUrl } from "./asaas_provider.ts";
import {
  asaasBaseUrlIsProduction,
  buildReadiness,
  handlePaymentsReadiness,
} from "./payments_readiness.ts";
import {
  handleScheduledWithdrawals,
  type PayoutDeps,
} from "./venue_payouts.ts";

Deno.test("a base de produção é só a URL oficial, sem barra", () => {
  assert(asaasBaseUrlIsProduction(asaasProductionBaseUrl));
  assert(asaasBaseUrlIsProduction(`${asaasProductionBaseUrl}/`));
  assert(!asaasBaseUrlIsProduction(asaasSandboxBaseUrl));
  assert(!asaasBaseUrlIsProduction(""));
  assert(!asaasBaseUrlIsProduction(undefined));
  assert(!asaasBaseUrlIsProduction("https://api.asaas.com.evil/v3"));
  assert(!asaasBaseUrlIsProduction("http://api.asaas.com/v3"));
});

Deno.test("a prontidão descarta texto e só guarda sim ou não", () => {
  const secret = "super-segredo-nao-vazar";
  const report = buildReadiness(
    {
      get: (name) => {
        if (name === "ASAAS_API_KEY") return secret;
        if (name === "ASAAS_BASE_URL") return asaasSandboxBaseUrl;
        if (name === "ASAAS_WEBHOOK_TOKEN") return "tok";
        if (name === "ASAAS_WEBHOOK_EMAIL") return "ops@example.com";
        return "   ";
      },
    },
    {
      vault_venue_withdrawals_url: true,
      vault_venue_withdrawals_secret: secret,
      venue_payouts_enabled: "true",
      cron_last_failed: true,
      cron_failure_code: secret,
      leaked: secret,
    },
  );
  assertEquals(report.asaas_api_key, true);
  assertEquals(report.asaas_base_url_production, false);
  assertEquals(report.asaas_webhook_token, true);
  assertEquals(report.asaas_webhook_email, true);
  assertEquals(report.venue_withdrawals_secret, false);
  assertEquals(report.vault_venue_withdrawals_url, true);
  assertEquals(report.vault_venue_withdrawals_secret, false);
  assertEquals(report.venue_payouts_enabled, false);
  assertEquals(report.cron_last_failed, true);
  assertEquals(report.cron_failure_code, null);
  assert(!JSON.stringify(report).includes(secret));
  assert(!JSON.stringify(report).includes("ops@example.com"));
});

Deno.test("produção ligada aparece sem devolver a URL", () => {
  const report = buildReadiness(
    {
      get: (name) =>
        name === "ASAAS_BASE_URL" ? `${asaasProductionBaseUrl}/` : "x",
    },
    {
      vault_venue_withdrawals_url: false,
      vault_venue_withdrawals_secret: false,
      venue_payouts_enabled: true,
      cron_last_failed: false,
      cron_failure_code: null,
    },
  );
  assertEquals(report.asaas_base_url_production, true);
  assertEquals(report.venue_payouts_enabled, true);
  assertEquals(report.cron_last_failed, false);
  assertEquals(report.cron_failure_code, null);
  assert(!JSON.stringify(report).includes("asaas.com"));
});

Deno.test("sem JWT a prontidão não revela o que está configurado", async () => {
  const secret = "chave-asaas-nao-sai";
  const response = await handlePaymentsReadiness(
    new Request("https://example.test/ready", { method: "POST" }),
    {
      env: { get: () => secret },
      loadVault: () => Promise.reject(new Error("não devia ler o vault")),
    },
  );
  assertEquals(response.status, 401);
  const body = await response.text();
  assert(!body.includes(secret));
});

Deno.test("quem não é admin recebe forbidden sem o mapa", async () => {
  const secret = "chave-asaas-nao-sai";
  const response = await handlePaymentsReadiness(
    new Request("https://example.test/ready", {
      method: "POST",
      headers: { authorization: "Bearer jwt-do-jogador" },
    }),
    {
      env: { get: () => secret },
      loadVault: () => Promise.reject(new Error("not admin")),
    },
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "forbidden" });
});

Deno.test("admin aal2 recebe só o mapa de sim ou não", async () => {
  const response = await handlePaymentsReadiness(
    new Request("https://example.test/ready", {
      method: "GET",
      headers: { authorization: "Bearer jwt-admin" },
    }),
    {
      env: {
        get: (name) =>
          name === "ASAAS_BASE_URL" ? asaasProductionBaseUrl : "valor-que-nao-sai",
      },
      loadVault: () =>
        Promise.resolve({
          vault_venue_withdrawals_url: true,
          vault_venue_withdrawals_secret: false,
          venue_payouts_enabled: false,
          cron_last_failed: true,
          cron_failure_code: "config_ausente",
        }),
    },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.asaas_base_url_production, true);
  assertEquals(body.vault_venue_withdrawals_url, true);
  assertEquals(body.vault_venue_withdrawals_secret, false);
  assertEquals(body.cron_failure_code, "config_ausente");
  assert(!JSON.stringify(body).includes("valor-que-nao-sai"));
});

Deno.test("cron sem VENUE_WITHDRAWALS_SECRET alerta e não autentica", async () => {
  const seen: string[] = [];
  const deps: PayoutDeps = {
    env: {
      get: (name) =>
        name === "SENTRY_DSN" ? "https://publickey@o1.ingest.sentry.io/123" : "",
    },
    store: {
      actor: () => Promise.resolve(null),
      verifiedTotp: () => Promise.resolve(false),
      isAdmin: () => Promise.resolve(false),
      rpc: () => Promise.reject(new Error("nao devia")),
      ownerEmail: () => Promise.resolve(""),
    },
    clientFor: () => {
      throw new Error("nao devia");
    },
    fetchFn: (_input, init) => {
      seen.push(String(init?.body ?? ""));
      return Promise.resolve(new Response("ok", { status: 200 }));
    },
  };
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST" }),
    deps,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "not authenticated");
  assertEquals(seen.length, 1);
  assert(seen[0].includes("venue_withdrawals_config_ausente"));
  assert(!seen[0].includes("publickey"));
});

Deno.test("a migration do cron levanta erro em vez de retornar calada", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261113160000_payments_readiness.sql",
      import.meta.url,
    ),
  );
  assert(sql.includes("raise exception 'venue_withdrawals_config_ausente: %'"));
  assert(
    !sql.includes(
      "if v_url is null or v_url = '' or v_secret is null or v_secret = '' then\n          return;",
    ),
  );
});
