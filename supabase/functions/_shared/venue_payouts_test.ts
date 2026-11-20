import { assertEquals } from "jsr:@std/assert@1";
import { handleScheduledWithdrawals, recentStrongAuth } from "./venue_payouts.ts";

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
      env: { get: (name) => name === "VENUE_WITHDRAWALS_SECRET" ? "segredo" : "" },
      store: {
        actor: () => Promise.resolve(null),
        verifiedTotp: () => Promise.resolve(false),
        isAdmin: () => Promise.resolve(false),
        rpc: () => Promise.resolve(null),
        ownerEmail: () => Promise.resolve(""),
      },
    },
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.provider, "woovi");
  assertEquals(body.mode, "depois_da_sessao");
});
