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

const officialAsaasHosts = new Set([
  "api.asaas.com",
  "api-sandbox.asaas.com",
  "asaas.com",
]);

function leaksOfficialAsaasHost(value: unknown): boolean {
  if (typeof value === "string") {
    if (officialAsaasHosts.has(value)) return true;
    try {
      return officialAsaasHosts.has(new URL(value).hostname);
    } catch {
      return false;
    }
  }
  if (Array.isArray(value)) return value.some(leaksOfficialAsaasHost);
  if (value !== null && typeof value === "object") {
    return Object.values(value).some(leaksOfficialAsaasHost);
  }
  return false;
}

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
  assertEquals(report.ledger_reconcile_secret, false);
  assertEquals(report.vault_venue_withdrawals_url, true);
  assertEquals(report.vault_venue_withdrawals_secret, false);
  assertEquals(report.venue_payouts_enabled, false);
  assertEquals(report.cron_last_failed, true);
  assertEquals(report.cron_failure_code, null);
  assert(!JSON.stringify(report).includes(secret));
  assert(!JSON.stringify(report).includes("ops@example.com"));
});

Deno.test("segredo só no vault conta como presente", () => {
  const report = buildReadiness(
    { get: () => "" },
    {
      vault_venue_withdrawals_secret: true,
      vault_ledger_reconcile_secret: true,
    },
  );
  assertEquals(report.venue_withdrawals_secret, true);
  assertEquals(report.ledger_reconcile_secret, true);
  assertEquals(report.vault_venue_withdrawals_secret, true);
  assertEquals(report.vault_ledger_reconcile_secret, true);
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
  assertEquals(leaksOfficialAsaasHost(report), false);
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

function cronDeps(secret: string): { deps: PayoutDeps; seen: string[] } {
  const seen: string[] = [];
  const deps: PayoutDeps = {
    env: {
      get: (name) => {
        if (name === "SENTRY_DSN") return "https://publickey@o1.ingest.sentry.io/123";
        if (name === "VENUE_WITHDRAWALS_SECRET") return secret;
        return "";
      },
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
  return { deps, seen };
}

Deno.test("sem segredo configurado responde 503 e não chama o Sentry", async () => {
  const first = cronDeps("");
  const again = cronDeps("   ");
  const empty = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST" }),
    first.deps,
  );
  const blank = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "qualquer" },
    }),
    again.deps,
  );
  assertEquals(empty.status, 503);
  assertEquals((await empty.json()).error, "config_ausente");
  assertEquals(blank.status, 503);
  assertEquals(first.seen.length, 0);
  assertEquals(again.seen.length, 0);
});

Deno.test("segredo errado responde 401 e não chama o Sentry", async () => {
  const { deps, seen } = cronDeps("cron-secret");
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "outro" },
    }),
    deps,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "not authenticated");
  assertEquals(seen.length, 0);
});

Deno.test("sem env o cron de saques aceita o segredo do vault", async () => {
  const calls: string[] = [];
  const cache = new Map<string, { value: string; until: number }>();
  const deps: PayoutDeps = {
    env: { get: () => "" },
    secretCache: cache,
    nowSec: 10,
    store: {
      actor: () => Promise.resolve(null),
      verifiedTotp: () => Promise.resolve(false),
      isAdmin: () => Promise.resolve(false),
      ownerEmail: () => Promise.resolve(""),
      rpc: (fn) => {
        calls.push(fn);
        if (fn === "cron_vault_secret") return Promise.resolve("segredo-vault");
        if (fn === "venue_payouts_enabled") return Promise.resolve(false);
        return Promise.resolve([]);
      },
    },
    clientFor: () => {
      throw new Error("nao devia");
    },
    fetchFn: () => Promise.reject(new Error("nao devia")),
  };
  const wrong = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "outro" },
    }),
    deps,
  );
  const again = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "segredo-vault" },
    }),
    deps,
  );
  assertEquals(wrong.status, 401);
  assertEquals(again.status, 200);
  assertEquals(calls.filter((name) => name === "cron_vault_secret").length, 1);
  assert(!JSON.stringify(await again.json()).includes("segredo-vault"));
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
