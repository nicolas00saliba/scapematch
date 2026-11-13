import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  compareLedger,
  handleLedgerReconcile,
  mapPaymentStatus,
  mapTransferStatus,
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
  asaasTransferId: "tra_1",
  status: "done",
  amountCents: 6000,
};

Deno.test("compara status, valor, livro e transferência", () => {
  const rows = compareLedger({
    payments: [
      { id: "pay_1", status: "pending", valueCents: 7900 },
      { id: "pay_fora", status: "paid", valueCents: 1000 },
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
    ],
    withdrawals: [
      withdrawal,
      {
        id: "saque-2",
        venueId: "11111111-1111-4111-8111-111111111111",
        externalReference: "saque-2",
        asaasTransferId: "tra_sumiu",
        status: "done",
        amountCents: 100,
      },
    ],
    truncated: false,
  });
  const kinds = rows.map((row) => row.kind).sort();
  assertEquals(kinds, [
    "charge_amount",
    "charge_missing_asaas",
    "charge_missing_local",
    "charge_status",
    "ledger_refund_missing",
    "transfer_missing_asaas",
    "transfer_missing_local",
    "transfer_status",
  ]);
});

Deno.test("status do Asaas vira o vocabulário do livro", () => {
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

Deno.test("lista incompleta não acusa ausência e marca o corte", () => {
  const rows = compareLedger({
    payments: [],
    transfers: [],
    charges: [paid],
    withdrawals: [withdrawal],
    truncated: true,
  });
  assertEquals(rows.map((row) => row.kind), ["asaas_truncated"]);
});

function envFor(secret: string): { get(name: string): string | undefined } {
  return {
    get(name) {
      if (name === "LEDGER_RECONCILE_SECRET") return secret;
      if (name === "ASAAS_BASE_URL") return "https://asaas.test/v3";
      if (name === "ASAAS_API_KEY") return "chave-de-teste";
      return "";
    },
  };
}

Deno.test("sem segredo responde 503 e não chama o Asaas", async () => {
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

Deno.test("segredo errado responde 401 e não chama o Asaas", async () => {
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
        const headers = init?.headers as { access_token?: string };
        seen.push({ url, key: headers.access_token ?? "" });
        assert((init?.method ?? "GET") === "GET");
        assert(!url.includes("chave-de-teste"));
        assert(!url.includes("chave-da-casa"));
        if (url.includes("/transfers/tra_1")) {
          return Promise.resolve(new Response(JSON.stringify({
            id: "tra_1",
            status: "DONE",
            value: 60,
            externalReference: "saque-1",
          }), { status: 200 }));
        }
        if (url.includes("/payments/pay_antiga")) {
          return Promise.resolve(new Response(JSON.stringify({
            id: "pay_antiga",
            status: "CONFIRMED",
            value: 10,
          }), { status: 200 }));
        }
        const data = url.includes("/payments") && url.includes("dateCreated")
          ? [{ id: "pay_1", status: "RECEIVED", value: 80 }]
          : [];
        return Promise.resolve(
          new Response(JSON.stringify({ data, hasMore: false }), { status: 200 }),
        );
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
                    provider_ref: "pay_1",
                    status: "pending",
                    amount_cents: 8000,
                    ledger_kinds: [],
                  },
                  {
                    id: "local-antiga",
                    provider_ref: "pay_antiga",
                    status: "paid",
                    amount_cents: 1000,
                    ledger_kinds: ["house_net"],
                  },
                ],
                withdrawals: [{
                  id: "saque-1",
                  venue_id: "11111111-1111-4111-8111-111111111111",
                  external_reference: "saque-1",
                  asaas_transfer_id: "tra_1",
                  status: "done",
                  amount_cents: 6000,
                }],
              },
              error: null,
            });
          }
          if (name === "read_venue_asaas_key") {
            return Promise.resolve({ data: "chave-da-casa", error: null });
          }
          if (name === "record_payment_divergences") {
            const rows = args.p_rows as Array<{ kind: string }>;
            assert(rows.some((row) => row.kind === "charge_status"));
            assert(!rows.some((row) => row.kind === "transfer_missing_asaas"));
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
  const paymentUrls = seen.filter((item) => item.url.includes("/payments"));
  const transferUrls = seen.filter((item) => item.url.includes("/transfers"));
  assert(paymentUrls.some((item) => item.url.includes("dateCreated%5Bge%5D=2026-11-12")));
  assert(paymentUrls.some((item) => item.url.includes("paymentDate%5Bge%5D=2026-11-12")));
  assert(paymentUrls.some((item) => item.url.endsWith("/payments/pay_antiga")));
  assert(paymentUrls.every((item) => item.key === "chave-de-teste"));
  assert(transferUrls.some((item) => item.url.endsWith("/transfers/tra_1")));
  assert(transferUrls.every((item) => item.key === "chave-da-casa"));
  assertEquals(calls, [
    "ledger_reconcile_snapshot",
    "read_venue_asaas_key",
    "record_payment_divergences",
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
                  asaas_transfer_id: "tra_1",
                  status: "done",
                  amount_cents: 6000,
                }],
              },
              error: null,
            });
          }
          if (name === "read_venue_asaas_key") {
            return Promise.resolve({ data: "", error: null });
          }
          if (name === "record_payment_divergences") {
            const rows = args.p_rows as Array<{ kind: string }>;
            assert(!rows.some((row) => row.kind === "transfer_missing_asaas"));
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
