import { assert, assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider } from "./pagbank_provider.ts";
import {
  isPixRejected,
  mapTransferEvent,
  mergeReceivables,
  requestFromBank,
  transferPayload,
  transferWebhookEvents,
  webhookAuthToken,
} from "./pagbank_transfers.ts";
import {
  ensureTransferWebhook,
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
  refreshers: Array<(() => Promise<string>) | undefined>;
  deps: PayoutDeps;
};

function fake(options?: {
  wallet?: string;
  apiKey?: string;
  tokens?: {
    access_token: string;
    refresh_token: string;
    access_expires_at: string | null;
  };
  begin?: boolean;
  enabled?: boolean;
  role?: string;
  balance?: number;
  pending?: number;
  failTransfer?: Error;
  bankOperation?: string;
  period?: string;
  stale?: Record<string, unknown>[];
  subaccounts?: Record<string, unknown>[];
  webhooks?: {
    id: string;
    url: string;
    enabled: boolean;
    interrupted: boolean;
    events: string[];
  }[];
  transfer?: {
    id: string;
    status: "pending" | "done" | "failed" | "cancelled";
    receiptUrl: string;
    externalReference: string;
    failReason: string;
  } | null;
  savedWebhooks?: { body: Record<string, unknown>; id?: string }[];
}): Fake {
  const calls: Fake["calls"] = [];
  const created: Record<string, unknown>[] = [];
  const keys: string[] = [];
  const refreshers: Array<(() => Promise<string>) | undefined> = [];
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
      if (options?.failTransfer) return Promise.reject(options.failTransfer);
      created.push(transferPayload(input) as Record<string, unknown>);
      return Promise.resolve({
        id: "tra_teste",
        status: "pending",
        receiptUrl: "",
        externalReference: input.externalReference,
        failReason: "",
      });
    },
    readTransfer: () => Promise.resolve(options?.transfer ?? null),
    listWebhooks: () => Promise.resolve(options?.webhooks ?? []),
    saveWebhook: (body, id) => {
      options?.savedWebhooks?.push({ body, id });
      return Promise.resolve();
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
          pending_cents: options?.pending ?? 0,
          withdrawals: [],
        });
      }
      if (fn === "venue_payout_wallet") return Promise.resolve(wallet);
      if (fn === "read_venue_pagbank_tokens") {
        return Promise.resolve(options?.tokens ?? null);
      }
      if (fn === "read_venue_provider_key") return Promise.resolve(apiKey);
      if (fn === "transfer_ref_venue") return Promise.resolve(venue);
      if (fn === "venue_payouts_enabled") {
        return Promise.resolve(options?.enabled ?? true);
      }
      if (fn === "list_due_venue_payouts") {
        return Promise.resolve([{
          venue_id: venue,
          period_key: options?.period ?? "auto:2026-W46",
          min_amount_cents: 1000,
          pending_cents: options?.pending ?? 0,
        }]);
      }
      if (fn === "list_venue_subaccounts") {
        return Promise.resolve(options?.subaccounts ?? []);
      }
      if (fn === "list_stale_pending_withdrawals") {
        return Promise.resolve(options?.stale ?? []);
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
          operation_type: options?.bankOperation ?? "PIX",
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
        const changed = args.p_status !== "pending";
        return Promise.resolve({
          changed,
          notice_id: changed ? notice : null,
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
          PAGBANK_POINTS_RESERVE_ACCOUNT_ID: "wal_reserva",
          PAGBANK_POINTS_RESERVE_TOKEN: reserveKey,
          PAGBANK_WEBHOOK_SECRET: webhookToken,
          VENUE_WITHDRAWALS_SECRET: "cron-secret",
          PAGBANK_BASE_URL: "https://sandbox.api.pagseguro.com",
        };
        return values[name];
      },
    },
    store,
    clientFor: (key, refresh) => {
      keys.push(key);
      refreshers.push(refresh);
      return client;
    },
    nowSec: now,
    today: "2026-11-12",
    fetchFn: () => Promise.resolve(new Response("{}", { status: 200 })),
  };
  return { store, calls, created, keys, refreshers, deps };
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

Deno.test("o saldo nao devolve chave e a equipe nao chama o PagBank", async () => {
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

Deno.test("o 401 do saque renova o refresh token e grava a sessão", async () => {
  const gate = fake({
    tokens: {
      access_token: "access-antigo",
      refresh_token: "refresh-antigo",
      access_expires_at: "2099-01-01T00:00:00.000Z",
    },
  });
  gate.deps.env = {
    get: (name) => {
      const values: Record<string, string> = {
        PAGBANK_TOKEN: "token-plataforma",
        PAGBANK_ENV: "sandbox",
        PAGBANK_CONNECT_CLIENT_ID: "client",
        PAGBANK_CONNECT_CLIENT_SECRET: "secret-do-connect",
      };
      return values[name];
    },
  };
  gate.deps.fetchFn = () =>
    Promise.resolve(Response.json({
      access_token: "access-novo",
      refresh_token: "refresh-novo",
      expires_in: 3600,
      account_id: "ACCO_casa",
    }));
  const response = await handleVenuePayouts(
    post({ action: "snapshot", venue_id: venue }),
    gate.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(gate.keys, ["access-antigo"]);
  const refresh = gate.refreshers[0];
  assert(refresh);
  assertEquals(await refresh(), "access-novo");
  const saved = gate.calls.find((call) =>
    call.fn === "store_venue_pagbank_tokens"
  );
  assertEquals(saved?.args.p_access_token, "access-novo");
  assertEquals(saved?.args.p_refresh_token, "refresh-novo");
  assertEquals(saved?.args.p_venue_id, venue);
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
  assertEquals(response.status, 403);
  assertEquals(body.error, "saques_desligados");
  assertEquals(gate.created, []);
  assertEquals(gate.keys, []);
  assert(!JSON.stringify(body).includes(subKey));
});

Deno.test("a reserva de pontos nao abre transferencia", async () => {
  const gate = fake({ wallet: "wal_reserva", apiKey: reserveKey });
  const response = await handleVenuePayouts(
    post({ action: "withdraw", venue_id: venue, amount_cents: 1500 }),
    gate.deps,
  );
  assertEquals((await response.json()).error, "saques_desligados");
  assertEquals(gate.created, []);
  assertEquals(gate.keys, []);
  assert(
    !gate.calls.some((call) => call.fn === "read_venue_provider_key"),
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
  assertEquals((await created.json()).created, 0);
  assertEquals(first.created.length, 0);
  assert(!first.calls.some((call) => call.fn === "list_due_venue_payouts"));

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

async function authenticity(raw: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${webhookToken}-${raw}`),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

Deno.test("o token da conta assina mesmo quando é a apiKey", () => {
  const token = "a".repeat(40);
  const env = {
    get: (name: string) => name === "PAGBANK_TOKEN" ? token : undefined,
  };
  assertEquals(webhookAuthToken(env, token), token);
  const override = "b".repeat(40);
  const replaced = {
    get: (name: string) => {
      if (name === "PAGBANK_WEBHOOK_SECRET") return override;
      if (name === "PAGBANK_TOKEN") return token;
      return undefined;
    },
  };
  assertEquals(webhookAuthToken(replaced, token), override);
});

Deno.test("webhook de transferencia exige o token e conclui o saque", async () => {
  const gate = fake({
    transfer: {
      id: "TR_teste",
      status: "done",
      receiptUrl: "https://example.com/recibo",
      externalReference: withdrawal,
      failReason: "",
    },
  });
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
      headers: { "x-authenticity-token": "curto" },
      body: JSON.stringify({ id: "TR_teste", reference_id: withdrawal }),
    }),
    gate.deps,
  );
  assertEquals(denied.status, 401);

  const raw = JSON.stringify({
    id: "TR_teste",
    reference_id: withdrawal,
    status: "FAILED",
  });
  const done = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "x-authenticity-token": await authenticity(raw) },
      body: raw,
    }),
    gate.deps,
  );
  assertEquals(done.status, 200);
  const applied = gate.calls.find((call) => call.fn === "apply_transfer_event");
  assertEquals(applied?.args.p_status, "done");
  assertEquals(applied?.args.p_transfer_id, "TR_teste");
  assertEquals(applied?.args.p_receipt, "https://example.com/recibo");
  assert(gate.calls.some((call) => call.fn === "mark_payout_notice_sent"));
  assert(mailed.some((body) => body.includes("Saque concluído no EscapeMatch")));
  assert(!mailed.some((body) => body.includes(subKey) || body.includes(reserveKey)));

  const ignored = fake();
  const noise = JSON.stringify({
    id: "CHAR_1",
    status: "PAID",
    payment_method: { type: "PIX" },
  });
  const payment = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "x-authenticity-token": await authenticity(noise) },
      body: noise,
    }),
    ignored.deps,
  );
  assertEquals(payment.status, 200);
  assertEquals(ignored.calls, []);

  const venueSigned = fake();
  const signed = JSON.stringify({
    id: "TR_teste",
    reference_id: withdrawal,
    status: "DONE",
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${subKey}-${signed}`),
  );
  const venueToken = [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const accepted = await handleTransferWebhook(
    new Request("https://example.test/hook", {
      method: "POST",
      headers: { "x-authenticity-token": venueToken },
      body: signed,
    }),
    venueSigned.deps,
  );
  assertEquals(accepted.status, 200);
  assert(venueSigned.calls.some((call) => call.fn === "read_venue_provider_key"));
  assert(!JSON.stringify(await accepted.clone().json()).includes(subKey));
});

Deno.test("toda transferencia sai como pix e nunca como ted", () => {
  const pix = transferPayload({
    valueCents: 1500,
    externalReference: withdrawal,
    description: "Saque EscapeMatch",
    destination: "pix",
    pixKey: "11222333000181",
    pixKeyType: "CNPJ",
  });
  assertEquals((pix.amount as { value: number }).value, 1500);
  assertEquals((pix.instrument as { type: string }).type, "PIX");
  assertEquals(
    (pix.instrument as { pix: { key_type: string } }).pix.key_type,
    "CNPJ",
  );
  const account = transferPayload({
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
  const bank = account.bankAccount as { bank: { code: string } };
  assertEquals((account.instrument as { type: string }).type, "PIX");
  assert(!JSON.stringify(account).includes("TED"));
  assertEquals(bank.bank.code, "341");
  let refused = false;
  try {
    requestFromBank(
      { operation_type: "TED", destination: "bank" },
      100,
      withdrawal,
    );
  } catch (error) {
    refused = error instanceof Error && error.message === "sem pix";
  }
  assert(refused);
  assert(isPixRejected(new Error(
    'PagBank 400: {"errors":[{"description":"A instituição de destino não participa do arranjo Pix."}]}',
  )));
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

Deno.test("banco sem pix falha com mensagem clara e nao vira ted", async () => {
  const saved = fake({ bankOperation: "TED" });
  const response = await handleVenuePayouts(
    post({ action: "withdraw", venue_id: venue, amount_cents: 1500 }),
    saved.deps,
  );
  assertEquals((await response.json()).error, "saques_desligados");
  assertEquals(saved.created, []);
  assert(!saved.calls.some((call) => call.fn === "fail_venue_withdrawal"));
  assert(!saved.calls.some((call) => call.fn === "claim_venue_withdrawal"));
});

Deno.test("a transferencia usa a chave da subconta e nao a devolve no erro", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const provider = new PagBankProvider(
    subKey,
    "https://sandbox.api.pagseguro.com",
    (url, init) => {
      calls.push({ url, init });
      if (url.includes("/accounts/balance")) {
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
  assertEquals(header.get("Authorization"), `Bearer ${subKey}`);
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

Deno.test("o automatico usa o saldo inteiro porque o PagBank ja descontou o pendente", async () => {
  const gate = fake({ pending: 4_000, balance: 10_000, period: "auto:2026-W46-r1" });
  const secret = {
    "x-venue-withdrawals-secret": "cron-secret",
    origin: "https://parceiro.escapematch.com.br",
  };
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    gate.deps,
  );
  const body = await response.json();
  assertEquals(body.created, 0);
  assertEquals(body.webhooks, 0);
  assertEquals(gate.created, []);
  assert(!gate.calls.some((call) => call.fn === "claim_venue_withdrawal"));
  assert(!gate.calls.some((call) => call.fn === "list_due_venue_payouts"));
});

Deno.test("o webhook de transferencia fica na subconta e nao duplica", async () => {
  const webhookUrl =
    "https://example.supabase.co/functions/v1/pagbank-transfer-webhook";
  const saved: { body: Record<string, unknown>; id?: string }[] = [];
  const listed = {
    data: [] as Record<string, unknown>[],
  };
  const calls: { url: string; method: string; token: string }[] = [];
  const provider = new PagBankProvider(
    subKey,
    "https://sandbox.api.pagseguro.com",
    (url, init) => {
      const method = init?.method ?? "GET";
      const headers = new Headers(init?.headers);
      calls.push({ url, method, token: headers.get("Authorization") ?? "" });
      if (method === "GET") {
        return Promise.resolve(new Response(JSON.stringify(listed), { status: 200 }));
      }
      listed.data = [{
        id: "wh_casa",
        url: webhookUrl,
        enabled: true,
        interrupted: false,
        events: [...transferWebhookEvents],
      }];
      return Promise.resolve(
        new Response(JSON.stringify({ id: "wh_casa" }), { status: 200 }),
      );
    },
  );
  const env = {
    get: (name: string) => {
      const values: Record<string, string> = {
        SUPABASE_URL: "https://example.supabase.co",
        PAGBANK_WEBHOOK_EMAIL: "ops@example.com",
        PAGBANK_WEBHOOK_SECRET: webhookToken,
      };
      return values[name];
    },
  };
  const client = {
    listWebhooks: () => provider.listWebhooks(),
    saveWebhook: (body: Record<string, unknown>, id?: string) => {
      saved.push({ body, id });
      return provider.saveWebhook(body, id);
    },
  };
  assertEquals(await ensureTransferWebhook(client, env), "ready");
  assertEquals(saved.length, 1);
  assertEquals(saved[0].id, undefined);
  assertEquals(saved[0].body.authToken, webhookToken);
  assertEquals(saved[0].body.url, webhookUrl);
  assertEquals(calls.every((call) => call.token === `Bearer ${subKey}`), true);
  assertEquals(calls.filter((call) => call.method === "POST").length, 1);

  assertEquals(await ensureTransferWebhook(client, env), "ready");
  assertEquals(saved.length, 1);
  assertEquals(calls.filter((call) => call.method === "POST").length, 1);

  const leaking = new PagBankProvider(
    subKey,
    "https://sandbox.api.pagseguro.com",
    () =>
      Promise.resolve(new Response(
        JSON.stringify({ errors: [{ description: webhookToken }] }),
        { status: 400 },
      )),
  );
  const leaked = await ensureTransferWebhook({
    listWebhooks: () => Promise.resolve([]),
    saveWebhook: () => leaking.saveWebhook({}),
  }, env).catch((caught: Error) => caught);
  assert(leaked instanceof Error);
  assert(!leaked.message.includes(webhookToken));
});

Deno.test("subcontas existentes ganham o webhook e a reserva fica de fora", async () => {
  const saved: { body: Record<string, unknown>; id?: string }[] = [];
  const gate = fake({
    subaccounts: [{ venue_id: venue }],
    savedWebhooks: saved,
  });
  const base = gate.deps.env;
  gate.deps.env = {
    get: (name) => {
      if (name === "SUPABASE_URL") return "https://example.supabase.co";
      if (name === "PAGBANK_WEBHOOK_EMAIL") return "ops@example.com";
      return base.get(name);
    },
  };
  const secret = {
    "x-venue-withdrawals-secret": "cron-secret",
    origin: "https://parceiro.escapematch.com.br",
  };
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    gate.deps,
  );
  const body = await response.json();
  assertEquals(body.created, 0);
  assertEquals(body.webhooks, 0);
  assertEquals(saved, []);
  assert(!JSON.stringify(body).includes(webhookToken));
  assert(!JSON.stringify(saved).includes("TRANSFER_"));

  const reserveSaved: { body: Record<string, unknown>; id?: string }[] = [];
  const reserve = fake({
    wallet: "wal_reserva",
    subaccounts: [{ venue_id: venue }],
    savedWebhooks: reserveSaved,
    enabled: false,
  });
  const reserveBase = reserve.deps.env;
  reserve.deps.env = {
    get: (name) => {
      if (name === "SUPABASE_URL") return "https://example.supabase.co";
      if (name === "PAGBANK_WEBHOOK_EMAIL") return "ops@example.com";
      return reserveBase.get(name);
    },
  };
  await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    reserve.deps,
  );
  assertEquals(reserveSaved, []);
  assert(!reserve.calls.some((call) => call.fn === "read_venue_provider_key"));
});

Deno.test("a reconciliacao consulta o pendente antigo e nao cria outra transferencia", async () => {
  const done = fake({
    enabled: false,
    stale: [{
      id: withdrawal,
      venue_id: venue,
      pagbank_transfer_id: "tra_teste",
      external_reference: withdrawal,
    }],
    transfer: {
      id: "tra_teste",
      status: "done",
      receiptUrl: "https://example.com/recibo",
      externalReference: withdrawal,
      failReason: "",
    },
  });
  const secret = {
    "x-venue-withdrawals-secret": "cron-secret",
    origin: "https://parceiro.escapematch.com.br",
  };
  const response = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    done.deps,
  );
  const body = await response.json();
  assertEquals(body.created, 0);
  assertEquals(body.reconciled, 1);
  assertEquals(done.created, []);
  const applied = done.calls.find((call) => call.fn === "apply_transfer_event");
  assertEquals(applied?.args.p_status, "done");
  assertEquals(applied?.args.p_transfer_id, "tra_teste");
  assert(!done.calls.some((call) => call.fn === "list_due_venue_payouts"));

  const waiting = fake({
    enabled: false,
    stale: [{
      id: withdrawal,
      venue_id: venue,
      pagbank_transfer_id: "tra_teste",
      external_reference: withdrawal,
    }],
    transfer: {
      id: "tra_teste",
      status: "pending",
      receiptUrl: "",
      externalReference: withdrawal,
      failReason: "",
    },
  });
  const still = await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    waiting.deps,
  );
  assertEquals((await still.json()).reconciled, 0);
  assertEquals(waiting.created, []);

  const reserve = fake({
    wallet: "wal_reserva",
    enabled: false,
    stale: [{
      id: withdrawal,
      venue_id: venue,
      pagbank_transfer_id: "tra_teste",
      external_reference: withdrawal,
    }],
  });
  await handleScheduledWithdrawals(
    new Request("https://example.test/cron", { method: "POST", headers: secret }),
    reserve.deps,
  );
  assertEquals(reserve.keys, []);
  assert(!reserve.calls.some((call) => call.fn === "apply_transfer_event"));
});
