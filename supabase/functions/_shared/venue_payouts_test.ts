import { assertEquals } from "jsr:@std/assert@1";
import {
  handleScheduledWithdrawals,
  recentStrongAuth,
  type PayoutDeps,
} from "./venue_payouts.ts";

function cronStore(calls: string[] = []): PayoutDeps["store"] {
  return {
    actor: () => Promise.resolve(null),
    verifiedTotp: () => Promise.resolve(false),
    isAdmin: () => Promise.resolve(false),
    rpc: (fn) => {
      calls.push(fn);
      return Promise.resolve(null);
    },
    ownerEmail: () => Promise.resolve(""),
  };
}

function cronDeps(secret: string, calls: string[] = []): {
  deps: PayoutDeps;
  fetches: { count: number };
} {
  const fetches = { count: 0 };
  const deps: PayoutDeps = {
    env: {
      get: (name) => name === "VENUE_WITHDRAWALS_SECRET" ? secret : "",
    },
    store: cronStore(calls),
    fetchFn: () => {
      fetches.count += 1;
      return Promise.resolve(new Response("ok"));
    },
  };
  return { deps, fetches };
}

Deno.test("reautenticacao exige senha recente ou totp em aal2", () => {
  const now = 1_000;
  assertEquals(
    recentStrongAuth({ amr: [{ method: "password", timestamp: now - 10 }] }, false, now),
    "ok",
  );
  assertEquals(recentStrongAuth({ amr: [] }, false, now), "reauth");
  assertEquals(
    recentStrongAuth({ aal: "aal2", amr: [{ method: "totp", timestamp: now }] }, true, now),
    "ok",
  );
});

Deno.test("o cron de saque não chama provedor antigo", async () => {
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "segredo" },
    }),
    {
      env: {
        get: (name) => name === "VENUE_WITHDRAWALS_SECRET" ? "segredo" : "",
      },
      store: cronStore(),
    },
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.provider, "woovi");
  assertEquals(body.mode, "depois_da_sessao");
});

Deno.test("segredo de cron errado ou ausente responde 401", async () => {
  const secret = "cron-secret";
  const wrongCalls: string[] = [];
  const wrongGate = cronDeps(secret, wrongCalls);
  const wrong = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", {
      method: "POST",
      headers: { "x-venue-withdrawals-secret": "outro" },
    }),
    wrongGate.deps,
  );
  assertEquals(wrong.status, 401);
  assertEquals((await wrong.json()).error, "not authenticated");
  assertEquals(wrongCalls, []);
  assertEquals(wrongGate.fetches.count, 0);

  const missingCalls: string[] = [];
  const missingGate = cronDeps(secret, missingCalls);
  const missing = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST" }),
    missingGate.deps,
  );
  assertEquals(missing.status, 401);
  assertEquals((await missing.json()).error, "not authenticated");
  assertEquals(missingCalls, []);
  assertEquals(missingGate.fetches.count, 0);
});
