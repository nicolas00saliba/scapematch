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
  asaasTransferId: "tra_1",
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
  assertEquals(seen, []);
  assertEquals(calls.filter((name) => name === "cron_vault_secret").length, 1);
  const body = await ok.json();
  assert(!JSON.stringify(body).includes("segredo-vault"));
});

Deno.test("a conciliação autenticada não consulta provedor", async () => {
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
        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(seen, []);
  const body = await response.json();
  assertEquals(body.ok, true);
  assertEquals(body.skipped, true);
  assertEquals(body.divergences, 0);
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
  assertEquals(seen, []);
  const body = await response.json();
  assertEquals(body.skipped, true);
});
