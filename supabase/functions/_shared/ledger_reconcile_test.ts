import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  compareLedger,
  handleLedgerReconcile,
  mapPaymentStatus,
  mapTransferStatus,
  remotePaymentStatus,
  saoPauloWindow,
  type LocalCharge,
  type LocalWithdrawal,
} from "./ledger_reconcile.ts";

const paid: LocalCharge = {
  id: "local-1",
  providerRef: "pay_1",
  status: "paid",
  amountCents: 8000,
  ledgerKinds: ["house_net"],
};

const withdrawal: LocalWithdrawal = {
  id: "saque-1",
  venueId: "11111111-1111-4111-8111-111111111111",
  externalReference: "saque-1",
  pagbankTransferId: "tra_1",
  status: "done",
  amountCents: 6000,
};

Deno.test("compara status, valor, livro e transferência", () => {
  const rows = compareLedger({
    payments: [
      { id: "pay_1", status: "pending", valueCents: 7900 },
      { id: "pay_fora", status: "paid", valueCents: 1000 },
      { id: "pay_credito", status: "refunded", valueCents: 500 },
    ],
    transfers: [
      {
        id: "tra_1",
        status: "pending",
        valueCents: 6000,
        externalReference: "saque-1",
      },
      {
        id: "tra_fora",
        status: "done",
        valueCents: 100,
        externalReference: "",
      },
    ],
    charges: [
      paid,
      {
        id: "local-2",
        providerRef: "pay_so_livro",
        status: "refunded",
        amountCents: 500,
        ledgerKinds: [],
      },
      {
        id: "local-3",
        providerRef: "pay_credito",
        status: "refunded",
        amountCents: 500,
        ledgerKinds: ["house_net"],
      },
    ],
    withdrawals: [
      withdrawal,
      {
        id: "saque-2",
        venueId: "11111111-1111-4111-8111-111111111111",
        externalReference: "saque-2",
        pagbankTransferId: "tra_sumiu",
        status: "done",
        amountCents: 100,
      },
    ],
    truncated: false,
  });
  const kinds = rows.map((row) => row.kind).sort();
  assertEquals(kinds, [
    "charge_amount",
    "charge_missing_local",
    "charge_missing_pagbank",
    "charge_status",
    "ledger_refund_missing",
    "transfer_missing_local",
    "transfer_missing_pagbank",
    "transfer_status",
  ]);
});

Deno.test("status do PagBank vira o vocabulário do livro", () => {
  assertEquals(mapPaymentStatus("AUTHORIZED"), "authorized");
  assertEquals(mapPaymentStatus("CONFIRMED"), "paid");
  assertEquals(mapPaymentStatus("RECEIVED_IN_CASH"), "paid");
  assertEquals(mapPaymentStatus("REFUND_REQUESTED"), "refunded");
  assertEquals(mapPaymentStatus("CHARGEBACK_REQUESTED"), null);
  assertEquals(mapTransferStatus("BANK_PROCESSING"), "pending");
  assertEquals(mapTransferStatus("BLOCKED"), null);
  const rows = compareLedger({
    payments: [{ id: "pay_1", status: null, valueCents: 8000 }],
    transfers: [{
      id: "tra_1",
      status: null,
      valueCents: 6000,
      externalReference: "saque-1",
    }],
    charges: [paid],
    withdrawals: [withdrawal],
    truncated: false,
  });
  assertEquals(rows.map((row) => row.kind).sort(), [
    "charge_status_unknown",
    "transfer_status_unknown",
  ]);
});

Deno.test("saque sem consulta da subconta não vira ausência", () => {
  const rows = compareLedger({
    payments: [],
    transfers: [],
    charges: [],
    withdrawals: [withdrawal],
    truncated: false,
    uncheckedWithdrawalIds: new Set([withdrawal.id]),
  });
  assertEquals(rows, []);
});

Deno.test("a janela usa o dia de São Paulo", () => {
  const window = saoPauloWindow(new Date("2026-11-13T02:30:00.000Z"));
  assertEquals(window.sinceDay, "2026-11-11");
  assertEquals(window.untilDay, "2026-11-12");
  assertEquals(window.sinceIso, "2026-11-11T03:00:00.000Z");
  assertEquals(window.untilIso, "2026-11-13T03:00:00.000Z");
});

Deno.test("pré-autorização cancelada bate com REFUNDED", () => {
  const rows = compareLedger({
    payments: [{ id: "pay_card", status: "refunded", valueCents: 8000 }],
    transfers: [],
    charges: [{
      id: "card-1",
      providerRef: "pay_card",
      status: "cancelled",
      amountCents: 8000,
      ledgerKinds: [],
    }],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

Deno.test("Pix apagado bate com cobrança cancelada", () => {
  assertEquals(
    remotePaymentStatus({ status: "PENDING", deleted: true, value: 80 }),
    "cancelled",
  );
  assertEquals(mapPaymentStatus("PENDING"), "pending");
  const rows = compareLedger({
    payments: [{ id: "pay_pix", status: "cancelled", valueCents: 8000 }],
    transfers: [],
    charges: [{
      id: "pix-1",
      providerRef: "pay_pix",
      status: "cancelled",
      amountCents: 8000,
      ledgerKinds: [],
    }],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

Deno.test("Pix estornado antes da confirmação não exige lançamento", () => {
  const rows = compareLedger({
    payments: [{ id: "pay_pix", status: "refunded", valueCents: 8000 }],
    transfers: [],
    charges: [{
      id: "pix-1",
      providerRef: "pay_pix",
      status: "refunded",
      amountCents: 8000,
      ledgerKinds: [],
    }],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

function settled(id: string, ref: string, status: string, kinds: string[]) {
  return {
    id,
    providerRef: ref,
    status,
    amountCents: 8000,
    ledgerKinds: kinds,
  };
}

Deno.test("roteiro: grupo confirma Pix e cartão", () => {
  const rows = compareLedger({
    payments: [
      { id: "pay_pix", status: "paid", valueCents: 8000 },
      { id: "pay_card", status: "paid", valueCents: 8000 },
    ],
    transfers: [],
    charges: [
      settled("pix", "pay_pix", "paid", ["house_net", "commission"]),
      settled("card", "pay_card", "paid", ["house_net", "commission"]),
    ],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

Deno.test("roteiro: grupo expira estorna o Pix e cancela a pré-auth", () => {
  const rows = compareLedger({
    payments: [
      { id: "pay_pix", status: "refunded", valueCents: 8000 },
      { id: "pay_card", status: "refunded", valueCents: 8000 },
    ],
    transfers: [],
    charges: [
      settled("pix", "pay_pix", "refunded", []),
      settled("card", "pay_card", "cancelled", []),
    ],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

Deno.test("roteiro: casa cancela depois da captura", () => {
  const kinds = ["house_net", "commission", "house_refund", "commission_refund"];
  const rows = compareLedger({
    payments: [
      { id: "pay_pix", status: "refunded", valueCents: 8000 },
      { id: "pay_card", status: "refunded", valueCents: 8000 },
    ],
    transfers: [],
    charges: [
      settled("pix", "pay_pix", "refunded", kinds),
      settled("card", "pay_card", "refunded", kinds),
    ],
    withdrawals: [],
    truncated: false,
  });
  assertEquals(rows, []);
});

Deno.test("lista incompleta não acusa ausência e marca o corte", () => {
  const rows = compareLedger({
    payments: [],
    transfers: [],
    charges: [paid],
    withdrawals: [withdrawal],
    truncated: true,
  });
  assertEquals(rows.map((row) => row.kind), ["pagbank_truncated"]);
});

function envFor(secret: string): { get(name: string): string | undefined } {
  return {
    get(name) {
      if (name === "LEDGER_RECONCILE_SECRET") return secret;
      if (name === "PAGBANK_BASE_URL") return "https://pagbank.test/v3";
      if (name === "PAGBANK_TOKEN") return "chave-de-teste";
      return "";
    },
  };
}

Deno.test("sem segredo responde 503 e não chama o PagBank", async () => {
  const seen: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", { method: "POST" }),
    {
      env: envFor(""),
      fetchFn: (input, init) => {
        seen.push(`${init?.method ?? "GET"} ${input}`);
        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    },
  );
  assertEquals(response.status, 503);
  assertEquals(seen, []);
});

Deno.test("segredo errado responde 401 e não chama o PagBank", async () => {
  const seen: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "outro" },
    }),
    {
      env: envFor("segredo-cron"),
      fetchFn: (input, init) => {
        seen.push(`${init?.method ?? "GET"} ${input}`);
        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    },
  );
  assertEquals(response.status, 401);
  assertEquals(seen, []);
});

Deno.test("sem env a conciliação aceita o segredo do vault", async () => {
  const seen: string[] = [];
  const calls: string[] = [];
  const cache = new Map<string, { value: string; until: number }>();
  const store = {
    rpc(name: string) {
      calls.push(name);
      if (name === "cron_vault_secret") {
        return Promise.resolve({ data: "segredo-vault", error: null });
      }
      if (name === "ledger_reconcile_snapshot") {
        return Promise.resolve({
          data: { charges: [], withdrawals: [], capped: false },
          error: null,
        });
      }
      if (name === "record_payment_divergences") {
        return Promise.resolve({ data: "run-vault", error: null });
      }
      return Promise.resolve({ data: null, error: { message: "inesperado" } });
    },
  };
  const wrong = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "outro" },
    }),
    {
      env: envFor(""),
      secretCache: cache,
      now: new Date(1_000),
      fetchFn: (input) => {
        seen.push(String(input));
        return Promise.resolve(new Response("{}", { status: 200 }));
      },
      store,
    },
  );
  assertEquals(wrong.status, 401);
  assertEquals(seen.length, 0);
  const ok = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-vault" },
    }),
    {
      env: envFor(""),
      secretCache: cache,
      now: new Date(2_000),
      fetchFn: (input) => {
        seen.push(String(input));
        return Promise.resolve(
          new Response(JSON.stringify({ data: [], hasMore: false }), {
            status: 200,
          }),
        );
      },
      store,
    },
  );
  assertEquals(ok.status, 200);
  assertEquals(seen, ["https://api.pagseguro.com/accounts/balance"]);
  assertEquals(calls.filter((name) => name === "cron_vault_secret").length, 1);
  const body = await ok.json();
  assert(!JSON.stringify(body).includes("segredo-vault"));
});

Deno.test("a conciliação consulta a subconta e o dia de São Paulo", async () => {
  const seen: Array<{ url: string; key: string }> = [];
  const calls: string[] = [];
  const now = new Date("2026-11-13T15:00:00.000Z");
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      now,
      fetchFn: (input, init) => {
        const url = String(input);
        const headers = new Headers(init?.headers);
        seen.push({ url, key: headers.get("Authorization") ?? "" });
        assert((init?.method ?? "GET") === "GET");
        assertEquals(headers.get("Accept"), "application/json");
        assertEquals(headers.get("Content-Type"), null);
        assert(!url.includes("chave-de-teste"));
        assert(!url.includes("chave-da-casa"));
        assert(!url.includes("dateCreated"));
        assert(!url.includes("paymentDate"));
        if (url.includes("/transfers/tra_1")) {
          return Promise.resolve(new Response(JSON.stringify({
            id: "tra_1",
            status: "DONE",
            amount: { value: 6000, currency: "BRL" },
            reference_id: "saque-1",
          }), { status: 200 }));
        }
        if (url.endsWith("/orders/ORDE_ANTIGA")) {
          return Promise.resolve(new Response(JSON.stringify({
            id: "ORDE_ANTIGA",
            charges: [{
              id: "CHAR_ANTIGA",
              status: "PAID",
              amount: { value: 1000, currency: "BRL" },
            }],
          }), { status: 200 }));
        }
        if (url.endsWith("/orders/ORDE_1")) {
          return Promise.resolve(new Response(JSON.stringify({
            id: "ORDE_1",
            charges: [{
              id: "CHAR_1",
              status: "PAID",
              amount: { value: 8000, currency: "BRL" },
            }],
          }), { status: 200 }));
        }
        return Promise.resolve(new Response("não", { status: 404 }));
      },
      store: {
        rpc(name, args) {
          calls.push(name);
          if (name === "ledger_reconcile_snapshot") {
            assertEquals(args.p_since, "2026-11-12T03:00:00.000Z");
            assertEquals(args.p_until, "2026-11-14T03:00:00.000Z");
            assert(!JSON.stringify(args).includes("chave-de-teste"));
            return Promise.resolve({
              data: {
                capped: false,
                charges: [
                  {
                    id: "local-1",
                    provider_ref: "ORDE_1",
                    status: "pending",
                    amount_cents: 8000,
                    ledger_kinds: [],
                  },
                  {
                    id: "local-antiga",
                    provider_ref: "ORDE_ANTIGA",
                    status: "paid",
                    amount_cents: 1000,
                    ledger_kinds: ["house_net"],
                  },
                ],
                withdrawals: [{
                  id: "saque-1",
                  venue_id: "11111111-1111-4111-8111-111111111111",
                  external_reference: "saque-1",
                  pagbank_transfer_id: "tra_1",
                  status: "done",
                  amount_cents: 6000,
                }],
              },
              error: null,
            });
          }
          if (name === "read_venue_provider_key") {
            return Promise.resolve({ data: "chave-da-casa", error: null });
          }
          if (name === "record_payment_divergences") {
            const rows = args.p_rows as Array<{ kind: string }>;
            assert(rows.some((row) => row.kind === "charge_status"));
            assert(!rows.some((row) => row.kind === "transfer_missing_pagbank"));
            assert(!JSON.stringify(rows).includes("chave-da-casa"));
            assert(!JSON.stringify(rows).includes("chave-de-teste"));
            return Promise.resolve({ data: "run-1", error: null });
          }
          return Promise.resolve({ data: null, error: { message: "inesperado" } });
        },
      },
    },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.ok, true);
  assert(body.divergences >= 1);
  const paymentUrls = seen.filter((item) => item.url.includes("/orders/"));
  const transferUrls = seen.filter((item) => item.url.includes("/transfers"));
  assert(paymentUrls.some((item) => item.url.endsWith("/orders/ORDE_1")));
  assert(paymentUrls.some((item) => item.url.endsWith("/orders/ORDE_ANTIGA")));
  assert(seen.every((item) => !item.url.includes("/charges")));
  assert(paymentUrls.every((item) => item.key === "Bearer chave-de-teste"));
  assert(transferUrls.some((item) => item.url.endsWith("/transfers/tra_1")));
  assert(transferUrls.every((item) => item.key === "Bearer chave-da-casa"));
  assertEquals(calls, [
    "ledger_reconcile_snapshot",
    "read_venue_provider_key",
    "record_payment_divergences",
    "low_balance_alert_cents",
  ]);
});

Deno.test("sem chave da subconta não consulta transferência", async () => {
  const seen: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      now: new Date("2026-11-13T15:00:00.000Z"),
      fetchFn: (input) => {
        seen.push(String(input));
        return Promise.resolve(
          new Response(JSON.stringify({ data: [], hasMore: false }), { status: 200 }),
        );
      },
      store: {
        rpc(name, args) {
          if (name === "ledger_reconcile_snapshot") {
            return Promise.resolve({
              data: {
                capped: false,
                charges: [],
                withdrawals: [{
                  id: "saque-1",
                  venue_id: "11111111-1111-4111-8111-111111111111",
                  external_reference: "saque-1",
                  pagbank_transfer_id: "tra_1",
                  status: "done",
                  amount_cents: 6000,
                }],
              },
              error: null,
            });
          }
          if (name === "read_venue_provider_key") {
            return Promise.resolve({ data: "", error: null });
          }
          if (name === "record_payment_divergences") {
            const rows = args.p_rows as Array<{ kind: string }>;
            assert(!rows.some((row) => row.kind === "transfer_missing_pagbank"));
            return Promise.resolve({ data: "run-1", error: null });
          }
          return Promise.resolve({ data: null, error: { message: "inesperado" } });
        },
      },
    },
  );
  assertEquals(response.status, 200);
  assert(seen.every((url) => !url.includes("/transfers")));
  void response;
});

function consultStore(
  charges: Record<string, unknown>[],
  saved?: { rows: Array<Record<string, string>> },
) {
  const calls: string[] = [];
  return {
    calls,
    rpc(name: string, args: Record<string, unknown>) {
      calls.push(name);
      if (name === "ledger_reconcile_snapshot") {
        return Promise.resolve({
          data: { capped: false, charges, withdrawals: [] },
          error: null,
        });
      }
      if (name === "record_payment_divergences") {
        if (saved) saved.rows = args.p_rows as Array<Record<string, string>>;
        return Promise.resolve({ data: "run-1", error: null });
      }
      return Promise.resolve({ data: null, error: { message: "inesperado" } });
    },
  };
}

function localCharge(
  ref: string,
  status: string,
  cents: number,
): Record<string, unknown> {
  return {
    id: `local-${ref}`,
    provider_ref: ref,
    status,
    amount_cents: cents,
    ledger_kinds: status === "paid" ? ["house_net"] : [],
  };
}

function paidOrder(orderId: string, chargeId: string, cents: number) {
  return {
    id: orderId,
    charges: [{
      id: chargeId,
      status: "PAID",
      amount: { value: cents, currency: "BRL" },
    }],
  };
}

async function withLogs(
  run: () => Promise<void>,
): Promise<string[]> {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map((item) => String(item)).join(" "));
  };
  try {
    await run();
  } finally {
    console.error = original;
  }
  return logs;
}

Deno.test("consulta pedido e cobrança por id, com o header da doc", async () => {
  const seen: string[] = [];
  const store = consultStore([
    localCharge("ORDE_OK", "paid", 8000),
    localCharge("CHAR_OK", "pending", 5000),
  ]);
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      now: new Date("2026-11-13T15:00:00.000Z"),
      fetchFn: (input, init) => {
        const url = String(input);
        seen.push(url);
        const headers = new Headers(init?.headers);
        assertEquals(init?.method, "GET");
        assertEquals(headers.get("Accept"), "application/json");
        assertEquals(headers.get("Content-Type"), null);
        assertEquals(headers.get("Authorization"), "Bearer chave-de-teste");
        if (url.endsWith("/orders/ORDE_OK")) {
          return Promise.resolve(
            new Response(JSON.stringify(paidOrder("ORDE_OK", "CHAR_OK_ORDEM", 8000)), {
              status: 200,
            }),
          );
        }
        if (url.includes("charge_id=CHAR_OK")) {
          return Promise.resolve(new Response(JSON.stringify({
            orders: [
              paidOrder("ORDE_OUTRO", "CHAR_OUTRO", 100),
              {
                id: "ORDE_CHAR",
                charges: [{
                  id: "CHAR_OK",
                  status: "WAITING",
                  amount: { value: 5000, currency: "BRL" },
                }],
              },
            ],
          }), { status: 200 }));
        }
        return Promise.resolve(new Response("não", { status: 404 }));
      },
      store,
    },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body, { ok: true, divergences: 0 });
  assert(seen.some((url) => url.endsWith("/orders/ORDE_OK")));
  assert(seen.some((url) => url.includes("/orders?charge_id=CHAR_OK")));
  assert(seen.every((url) => !url.includes("dateCreated") && !url.includes("paymentDate")));
  assert(seen.every((url) => !url.includes("/charges")));
  assert(store.calls.includes("record_payment_divergences"));
});

Deno.test("406 na consulta do pedido alerta, grava a falha e não vaza o token", async () => {
  const saved: { rows: Array<Record<string, string>> } = { rows: [] };
  const store = consultStore([localCharge("ORDE_RECUSADO", "paid", 8000)], saved);
  let status = 0;
  let body = "";
  const logs = await withLogs(async () => {
    const response = await handleLedgerReconcile(
      new Request("https://example.test/ledger", {
        method: "POST",
        headers: { "x-ledger-reconcile-secret": "segredo-cron" },
      }),
      {
        env: envFor("segredo-cron"),
        fetchFn: () =>
          Promise.resolve(
            new Response("Not Acceptable chave-de-teste", { status: 406 }),
          ),
        store,
      },
    );
    status = response.status;
    body = await response.text();
  });
  assertEquals(status, 502);
  const parsed = JSON.parse(body);
  assertEquals(parsed.error, "pagbank_unavailable");
  assertEquals(parsed.failures, 1);
  assert(!body.includes("chave-de-teste"));
  assert(logs.some((line) =>
    line.includes("ledger-reconcile") && line.includes("406") &&
    line.includes("pagbank_unavailable")
  ));
  assert(logs.every((line) => !line.includes("chave-de-teste")));
  assert(store.calls.includes("record_payment_divergences"));
  assert(saved.rows.some((row) =>
    row.providerRef === "ORDE_RECUSADO" && row.actual === "406"
  ));
});

Deno.test("404 de uma cobrança segue para a próxima e registra ausência", async () => {
  const store = consultStore([
    localCharge("ORDE_SUMIU", "paid", 8000),
    localCharge("ORDE_OK", "paid", 1500),
  ]);
  const seen: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      fetchFn: (input) => {
        const url = String(input);
        seen.push(url);
        if (url.endsWith("/orders/ORDE_SUMIU")) {
          return Promise.resolve(new Response("não", { status: 404 }));
        }
        return Promise.resolve(
          new Response(JSON.stringify(paidOrder("ORDE_OK", "CHAR_OK", 1500)), {
            status: 200,
          }),
        );
      },
      store,
    },
  );
  assertEquals(response.status, 200);
  assert(seen.some((url) => url.endsWith("/orders/ORDE_SUMIU")));
  assert(seen.some((url) => url.endsWith("/orders/ORDE_OK")));
  assert(store.calls.includes("record_payment_divergences"));
});

Deno.test("406 numa cobrança segue para a próxima, grava a falha e alerta", async () => {
  const saved: { rows: Array<{ kind: string; providerRef: string; actual: string }> } = {
    rows: [],
  };
  const store = consultStore([
    localCharge("ORDE_RECUSADO", "paid", 8000),
    localCharge("ORDE_OK", "pending", 1500),
  ], saved);
  const seen: string[] = [];
  let body = "";
  const logs = await withLogs(async () => {
    const response = await handleLedgerReconcile(
      new Request("https://example.test/ledger", {
        method: "POST",
        headers: { "x-ledger-reconcile-secret": "segredo-cron" },
      }),
      {
        env: envFor("segredo-cron"),
        fetchFn: (input) => {
          const url = String(input);
          seen.push(url);
          if (url.endsWith("/orders/ORDE_RECUSADO")) {
            return Promise.resolve(
              new Response("Not Acceptable chave-de-teste", { status: 406 }),
            );
          }
          return Promise.resolve(
            new Response(JSON.stringify(paidOrder("ORDE_OK", "CHAR_OK", 1500)), {
              status: 200,
            }),
          );
        },
        store,
      },
    );
    assertEquals(response.status, 502);
    body = await response.text();
  });
  const parsed = JSON.parse(body);
  assertEquals(parsed.error, "pagbank_unavailable");
  assertEquals(parsed.failures, 1);
  assert(parsed.divergences >= 1);
  assert(!body.includes("chave-de-teste"));
  assert(seen.some((url) => url.endsWith("/orders/ORDE_RECUSADO")));
  assert(seen.some((url) => url.endsWith("/orders/ORDE_OK")));
  assert(saved.rows.some((row) =>
    row.providerRef === "ORDE_RECUSADO" && row.actual === "406"
  ));
  assert(saved.rows.some((row) =>
    row.kind === "charge_status" && row.providerRef === "ORDE_OK"
  ));
  assert(logs.some((line) =>
    line.includes("ledger-reconcile") && line.includes("406")
  ));
  assert(logs.every((line) => !line.includes("chave-de-teste")));
});

Deno.test("timeout numa cobrança segue para a próxima e alerta sem segredo", async () => {
  const saved: { rows: Array<Record<string, string>> } = { rows: [] };
  const store = consultStore([
    localCharge("ORDE_LENTO", "paid", 8000),
    localCharge("ORDE_OK", "paid", 1500),
  ], saved);
  const seen: string[] = [];
  let body = "";
  const logs = await withLogs(async () => {
    const response = await handleLedgerReconcile(
      new Request("https://example.test/ledger", {
        method: "POST",
        headers: { "x-ledger-reconcile-secret": "segredo-cron" },
      }),
      {
        env: envFor("segredo-cron"),
        fetchFn: (input) => {
          const url = String(input);
          seen.push(url);
          if (url.endsWith("/orders/ORDE_LENTO")) {
            return Promise.reject(
              new DOMException("The signal has been aborted", "TimeoutError"),
            );
          }
          return Promise.resolve(
            new Response(JSON.stringify(paidOrder("ORDE_OK", "CHAR_OK", 1500)), {
              status: 200,
            }),
          );
        },
        store,
      },
    );
    assertEquals(response.status, 502);
    body = await response.text();
  });
  assert(!body.includes("chave-de-teste"));
  const parsed = JSON.parse(body);
  assertEquals(parsed.error, "pagbank_unavailable");
  assertEquals(parsed.failures, 1);
  assert(seen.some((url) => url.endsWith("/orders/ORDE_LENTO")));
  assert(seen.some((url) => url.endsWith("/orders/ORDE_OK")));
  assert(logs.some((line) => line.includes("408") && line.includes("ledger-reconcile")));
  assert(logs.every((line) => !line.includes("chave-de-teste")));
  assert(store.calls.includes("record_payment_divergences"));
  assert(saved.rows.some((row) =>
    row.providerRef === "ORDE_LENTO" && row.actual === "408"
  ));
});

Deno.test("paginação local consulta todas as cobranças, sem offset de data", async () => {
  const charges = Array.from({ length: 51 }, (_, index) =>
    localCharge(`ORDE_${index}`, "paid", 1000));
  const store = consultStore(charges);
  const seen: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      fetchFn: (input) => {
        const url = String(input);
        seen.push(url);
        const id = url.split("/").pop() ?? "";
        return Promise.resolve(
          new Response(JSON.stringify(paidOrder(id, `CHAR_${id}`, 1000)), {
            status: 200,
          }),
        );
      },
      store,
    },
  );
  assertEquals(response.status, 200);
  const orders = seen.filter((url) => url.includes("/orders/ORDE_"));
  assertEquals(orders.length, 51);
  assert(seen.some((url) => url.endsWith("/accounts/balance")));
  assert(seen.every((url) => !url.includes("offset=") && !url.includes("dateCreated")));
  assert(store.calls.includes("record_payment_divergences"));
});

Deno.test("saldo da conta PJ abaixo do limite alerta e no limite não", async () => {
  async function run(cents: number): Promise<string[]> {
    const lines: string[] = [];
    const original = console.error;
    console.error = (line?: unknown) => {
      lines.push(String(line ?? ""));
    };
    try {
      const response = await handleLedgerReconcile(
        new Request("https://example.test/ledger", {
          method: "POST",
          headers: { "x-ledger-reconcile-secret": "segredo-cron" },
        }),
        {
          env: envFor("segredo-cron"),
          fetchFn: (input) => {
            const url = String(input);
            if (url.endsWith("/accounts/balance")) {
              return Promise.resolve(
                new Response(JSON.stringify({ balance: cents }), { status: 200 }),
              );
            }
            return Promise.resolve(
              new Response(JSON.stringify({ data: [], hasMore: false }), {
                status: 200,
              }),
            );
          },
          store: {
            rpc(name: string) {
              if (name === "ledger_reconcile_snapshot") {
                return Promise.resolve({
                  data: { charges: [], withdrawals: [], capped: false },
                  error: null,
                });
              }
              if (name === "record_payment_divergences") {
                return Promise.resolve({ data: "run-saldo", error: null });
              }
              if (name === "low_balance_alert_cents") {
                return Promise.resolve({ data: 100_000, error: null });
              }
              return Promise.resolve({ data: null, error: { message: "inesperado" } });
            },
          },
        },
      );
      assertEquals(response.status, 200);
      const body = await response.text();
      assert(!body.includes("transfers"));
      assert(!body.includes(String(cents)));
    } finally {
      console.error = original;
    }
    return lines;
  }

  const low = await run(99_999);
  assert(low.some((line) =>
    line.includes('"scope":"pagbank-balance"') &&
    line.includes('"code":"low_balance"')
  ));
  assert(low.every((line) => !line.includes("99999")));
  const enough = await run(100_000);
  assertEquals(enough.some((line) => line.includes("low_balance")), false);
  const above = await run(100_001);
  assertEquals(above.some((line) => line.includes("low_balance")), false);
});
