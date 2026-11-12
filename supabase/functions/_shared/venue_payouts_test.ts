import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "./asaas_provider.ts";
import {
  mapTransferEvent,
  mergeReceivables,
  transferPayload,
} from "./asaas_transfers.ts";
import {
  handleScheduledWithdrawals,
  handleTransferWebhook,
  handleVenuePayouts,
  readJwtClaims,
  recentStrongAuth,
  type PayoutDeps,
  type PayoutStore,
  type TransferClient,
} from "./venue_payouts.ts";

const venue = "b1111111-1111-4111-8111-111111111111";
const actor = "a1111111-1111-4111-8111-111111111111";
const withdrawal = "c1111111-1111-4111-8111-111111111111";
const notice = "d1111111-1111-4111-8111-111111111111";
const now = 1_700_000_000;
const subKey = "sub-account-key-do-not-log";
const reserveKey = "reserve-key-do-not-log";
const webhookToken = "webhook-token-with-32-characters-min";

function token(claims: Record<string, unknown>): string {
  const payload = btoa(JSON.stringify(claims))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `h.${payload}.s`;
}

function freshToken(extra: Record<string, unknown> = {}): string {
  return token({
    sub: actor,
    aal: "aal1",
    amr: [{ method: "password", timestamp: now - 20 }],
    ...extra,
  });
}

type Fake = {
  store: PayoutStore;
  calls: { fn: string; args: Record<string, unknown> }[];
  created: Record<string, unknown>[];
  keys: string[];
  deps: PayoutDeps;
};

function fake(options?: {
  wallet?: string;
  apiKey?: string;
  begin?: boolean;
  enabled?: boolean;
  role?: string;
  balance?: number;
}): Fake {
  const calls: Fake["calls"] = [];
  const created: Record<string, unknown>[] = [];
  const keys: string[] = [];
  const wallet = options?.wallet ?? "wal_casa";
  const apiKey = options?.apiKey ?? subKey;
  const client: TransferClient = {
    balanceCents: () => Promise.resolve(options?.balance ?? 10_000),
    receivables: () =>
      Promise.resolve([
        { cents: 3200, creditDate: "2026-11-18", description: "Grupo" },
      ]),
    findTransfer: () => Promise.resolve(null),
    createTransfer: (input) => {
      created.push(transferPayload(input) as Record<string, unknown>);
      return Promise.resolve({
        id: "tra_teste",
        status: "pending",
        receiptUrl: "",
        externalReference: input.externalReference,
        failReason: "",
      });
    },
  };
  const store: PayoutStore = {
    actor: (jwt) => {
      const claims = readJwtClaims(jwt);
      if (claims.sub !== actor) return Promise.resolve(null);
      return Promise.resolve({ id: actor, email: "dona@example.com" });
    },
    verifiedTotp: () => Promise.resolve(false),
    isAdmin: () => Promise.resolve(false),
    ownerEmail: () => Promise.resolve("dona@example.com"),
    rpc: (fn, args) => {
      calls.push({ fn, args });
      if (fn === "venue_payout_snapshot") {
        return Promise.resolve({
          enabled: options?.enabled ?? true,
          can_withdraw: (options?.role ?? "owner") !== "staff",
          role: options?.role ?? "owner",
          pending_cents: 0,
          withdrawals: [],
        });
      }
      if (fn === "venue_payout_wallet") return Promise.resolve(wallet);
      if (fn === "read_venue_asaas_key") return Promise.resolve(apiKey);
      if (fn === "venue_payouts_enabled") {
        return Promise.resolve(options?.enabled ?? true);
      }
      if (fn === "list_due_venue_payouts") {
        return Promise.resolve([{
          venue_id: venue,
          period_key: "auto:2026-11-12",
          min_amount_cents: 1000,
          pending_cents: 0,
        }]);
      }
      if (fn === "claim_venue_withdrawal") {
        return Promise.resolve({
          id: withdrawal,
          amount_cents: args.p_amount_cents,
          fresh: true,
        });
      }
      if (fn === "begin_withdrawal_dispatch") {
        return Promise.resolve(options?.begin ?? true);
      }
      if (fn === "venue_bank_for_transfer") {
        return Promise.resolve({
          destination: "pix",
          pix_key: "11222333000181",
          pix_key_type: "CNPJ",
          operation_type: "PIX",
          owner_name: "Casa do Saque",
          owner_document: "11222333000181",
        });
      }
      if (fn === "save_venue_bank_account") return Promise.resolve(notice);
      if (fn === "payout_notice") {
        return Promise.resolve({
          id: notice,
          owner_id: actor,
          kind: "withdrawal_done",
          body: "O saque da casa foi concluído.",
          sent_at: null,
        });
      }
      if (fn === "apply_transfer_event") {
        return Promise.resolve({
          changed: true,
          notice_id: notice,
          status: args.p_status,
        });
      }
      if (fn === "unsent_payout_notices") return Promise.resolve([]);
      return Promise.resolve(null);
    },
  };
  const deps: PayoutDeps = {
    env: {
      get: (name) => {
        const values: Record<string, string> = {
          ASAAS_POINTS_RESERVE_WALLET_ID: "wal_reserva",
          ASAAS_POINTS_RESERVE_API_KEY: reserveKey,
          ASAAS_WEBHOOK_TOKEN: webhookToken,
          VENUE_WITHDRAWALS_SECRET: "cron-secret",
          ASAAS_BASE_URL: "https://api-sandbox.asaas.com/v3",
        };
        return values[name];
      },
    },
    store,
    clientFor: (key) => {
      keys.push(key);
      return client;
    },
    nowSec: now,
    today: "2026-11-12",
    fetchFn: () => Promise.resolve(new Response("{}", { status: 200 })),
  };
  return { store, calls, created, keys, deps };
}

function post(body: unknown, jwt = freshToken()): Request {
  return new Request("https://parceiro.escapematch.com.br/fn", {
    method: "POST",
    headers: {
      authorization: `Bearer ${jwt}`,
      origin: "https://parceiro.escapematch.com.br",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("reautenticacao exige senha recente ou totp em aal2", () => {
  assertEquals(
    recentStrongAuth(
      { aal: "aal1", amr: [{ method: "password", timestamp: now - 20 }] },
      false,
      now,
    ),
    "ok",
  );
  assertEquals(
    recentStrongAuth(
      { aal: "aal1", amr: [{ method: "password", timestamp: now - 301 }] },
      false,
      now,
    ),
    "reauth",
  );
  assertEquals(
    recentStrongAuth(
      { aal: "aal1", amr: [{ method: "otp", timestamp: now - 10 }] },
      false,
      now,
    ),
    "ok",
  );
  assertEquals(
    recentStrongAuth(
      { aal: "aal1", amr: [{ method: "password", timestamp: now - 10 }] },
      true,
      now,
    ),
    "mfa",
  );
  assertEquals(
    recentStrongAuth(
      { aal: "aal2", amr: [{ method: "totp", timestamp: now - 10 }] },
      true,
      now,
    ),
    "ok",
  );
});

Deno.test("o saldo nao devolve chave e a equipe nao chama o Asaas", async () => {
  const owner = fake();
  const response = await handleVenuePayouts(
    post({ action: "snapshot", venue_id: venue }),
    owner.deps,
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.available_cents, 10_000);
  assertEquals(body.receivables[0].creditDate, "2026-11-18");
  assertEquals(owner.keys, [subKey]);
  assert(!JSON.stringify(body).includes(subKey));
  assert(!JSON.stringify(body).includes(reserveKey));

  const staff = fake({ role: "staff" });
  const locked = await handleVenuePayouts(
    post({ action: "snapshot", venue_id: venue }),
    staff.deps,
  );
  const lockedBody = await locked.json();
  assertEquals(lockedBody.can_withdraw, false);
  assertEquals(staff.keys, []);
});

Deno.test("saque manual sem reauth nao transfere", async () => {
  const gate = fake();
  const stale = token({
    sub: actor,
    aal: "aal1",
    amr: [{ method: "password", timestamp: now - 600 }],
  });
  const response = await handleVenuePayouts(
    post({ action: "withdraw", venue_id: venue, amount_cents: 1500 }, stale),
    gate.deps,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "reauth");
  assertEquals(gate.created, []);
  assertEquals(gate.keys, []);
});

Deno.test("saque manual manda a chave da subconta e a referencia unica", async () => {
  const gate = fake();
  const response = await handleVenuePayouts(
    post({ action: "withdraw", venue_id: venue, amount_cents: 1500 }),
    gate.deps,
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.status, "pending");
  assertEquals(gate.keys, [subKey]);
  assertEquals(gate.created.length, 1);
  const payload = gate.created[0];
  assertEquals(payload.pixAddressKey, "11222333000181");
  assertEquals(payload.externalReference, withdrawal);
  assert(!JSON.stringify(body).includes("11222333000181"));
  assert(!JSON.stringify(body).includes(subKey));
  const claim = gate.calls.find((call) => call.fn === "claim_venue_withdrawal");
  assertEquals(claim?.args.p_actor, actor);
  assertEquals(claim?.args.p_source, "manual");
});

Deno.test("a reserva de pontos nao abre transferencia", async () => {
  const gate = fake({ wallet: "wal_reserva", apiKey: reserveKey });
  const response = await handleVenuePayouts(
    post({ action: "withdraw", venue_id: venue, amount_cents: 1500 }),
    gate.deps,
  );
  assertEquals((await response.json()).error, "reserva");
  assertEquals(gate.created, []);
  assertEquals(gate.keys, []);
  assert(
    !gate.calls.some((call) => call.fn === "read_venue_asaas_key"),
  );
});

Deno.test("o cron nao repete o periodo e ignora a reserva", async () => {
  const first = fake();
  const secret = {
    "x-venue-withdrawals-secret": "cron-secret",
    origin: "https://parceiro.escapematch.com.br",
  };
  const created = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    first.deps,
  );
  assertEquals((await created.json()).created, 1);
  assertEquals(first.created.length, 1);

  const again = fake({ begin: false });
  const repeat = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    again.deps,
  );
  assertEquals((await repeat.json()).created, 0);
  assertEquals(again.created, []);

  const reserve = fake({ wallet: "wal_reserva" });
  const skipped = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    reserve.deps,
  );
  assertEquals((await skipped.json()).created, 0);
  assertEquals(reserve.keys, []);

  const off = fake({ enabled: false });
  const disabled = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    off.deps,
  );
  assertEquals((await disabled.json()).created, 0);
  assert(!off.calls.some((call) => call.fn === "list_due_venue_payouts"));
});

Deno.test("webhook de transferencia exige o token e conclui o saque", async () => {
  const gate = fake();
  const baseEnv = gate.deps.env;
  const mailed: string[] = [];
  gate.deps.env = {
    get: (name) => {
      if (name === "RESEND_API_KEY") return "re_test_key";
      if (name === "PAYOUT_MAIL_FROM") return "EscapeMatch <aviso@example.com>";
      return baseEnv.get(name);
    },
  };
  gate.deps.fetchFn = (_input, init) => {
    mailed.push(String(init?.body ?? ""));
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const denied = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "asaas-access-token": "curto" },
      body: JSON.stringify({ event: "TRANSFER_DONE" }),
    }),
    gate.deps,
  );
  assertEquals(denied.status, 401);

  const done = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "asaas-access-token": webhookToken },
      body: JSON.stringify({
        event: "TRANSFER_DONE",
        transfer: {
          id: "tra_teste",
          externalReference: withdrawal,
          transactionReceiptUrl: "https://example.com/recibo",
        },
      }),
    }),
    gate.deps,
  );
  assertEquals(done.status, 200);
  const applied = gate.calls.find((call) => call.fn === "apply_transfer_event");
  assertEquals(applied?.args.p_status, "done");
  assertEquals(applied?.args.p_receipt, "https://example.com/recibo");
  assert(gate.calls.some((call) => call.fn === "mark_payout_notice_sent"));
  assert(mailed.some((body) => body.includes("Saque concluído no EscapeMatch")));
  assert(!mailed.some((body) => body.includes(subKey) || body.includes(reserveKey)));

  const ignored = fake();
  const payment = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "asaas-access-token": webhookToken },
      body: JSON.stringify({ event: "PAYMENT_RECEIVED", payment: { id: "pay" } }),
    }),
    ignored.deps,
  );
  assertEquals(payment.status, 200);
  assertEquals(ignored.calls, []);
});

Deno.test("pix e ted montam o corpo sem a chave da api", () => {
  const pix = transferPayload({
    valueCents: 1500,
    externalReference: withdrawal,
    description: "Saque EscapeMatch",
    destination: "pix",
    pixKey: "11222333000181",
    pixKeyType: "CNPJ",
  });
  assertEquals(pix.value, 15);
  assertEquals(pix.pixAddressKeyType, "CNPJ");
  const ted = transferPayload({
    valueCents: 2000,
    externalReference: withdrawal,
    description: "Saque EscapeMatch",
    destination: "bank",
    operationType: "TED",
    bankCode: "341",
    agency: "0001",
    accountNumber: "12345",
    accountDigit: "6",
    ownerName: "Casa",
    ownerDocument: "11222333000181",
  });
  const bank = ted.bankAccount as { bank: { code: string } };
  assertEquals(ted.operationType, "TED");
  assertEquals(bank.bank.code, "341");
  assertEquals(mapTransferEvent("TRANSFER_FAILED"), "failed");
  assertEquals(mapTransferEvent("PAYMENT_RECEIVED"), null);
  assertEquals(
    mergeReceivables(
      [{ cents: 1000, creditDate: "2026-11-20", description: "Cobrança" }],
      [{ cents: 500, date: "2026-11-18", description: "Futuro", type: "TRANSFER" }],
      "2026-11-12",
    ).map((item) => item.creditDate),
    ["2026-11-18", "2026-11-20"],
  );
});

Deno.test("a transferencia usa a chave da subconta e nao a devolve no erro", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const provider = new AsaasProvider(
    subKey,
    "https://api-sandbox.asaas.com/v3",
    (url, init) => {
      calls.push({ url, init });
      if (url.includes("/finance/balance")) {
        return Promise.resolve(
          new Response(JSON.stringify({ balance: 12.5 }), { status: 200 }),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({ errors: [{ code: "invalid_value", description: subKey }] }),
          { status: 400 },
        ),
      );
    },
  );
  assertEquals(await provider.financeBalanceCents(), 1250);
  const header = new Headers(calls[0].init?.headers);
  assertEquals(header.get("access_token"), subKey);
  const error = await provider.createTransfer({
    valueCents: 100,
    externalReference: withdrawal,
    description: "Saque EscapeMatch",
    destination: "pix",
    pixKey: "11222333000181",
    pixKeyType: "CNPJ",
  }).catch((caught: Error) => caught);
  assert(error instanceof Error);
  assert(!error.message.includes(subKey));
});
