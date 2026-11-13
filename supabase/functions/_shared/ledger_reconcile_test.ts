import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  compareLedger,
  handleLedgerReconcile,
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

Deno.test("a conciliação só faz GET e grava a divergência", async () => {
  const seen: string[] = [];
  const calls: string[] = [];
  const response = await handleLedgerReconcile(
    new Request("https://example.test/ledger", {
      method: "POST",
      headers: { "x-ledger-reconcile-secret": "segredo-cron" },
    }),
    {
      env: envFor("segredo-cron"),
      fetchFn: (input, init) => {
        const method = init?.method ?? "GET";
        seen.push(`${method} ${input}`);
        assert(method === "GET");
        assert(!String(input).includes("chave-de-teste"));
        const path = String(input).includes("/transfers") ? "transfer" : "payment";
        const data = path === "payment"
          ? [{ id: "pay_1", status: "RECEIVED", value: 80 }]
          : [{
            id: "tra_1",
            status: "DONE",
            value: 60,
            externalReference: "saque-1",
          }];
        return Promise.resolve(
          new Response(JSON.stringify({ data, hasMore: false }), {
            status: 200,
          }),
        );
      },
      store: {
        rpc(name, args) {
          calls.push(name);
          if (name === "ledger_reconcile_snapshot") {
            assert(!JSON.stringify(args).includes("chave-de-teste"));
            return Promise.resolve({
              data: {
                capped: false,
                charges: [{
                  id: "local-1",
                  provider_ref: "pay_1",
                  status: "pending",
                  amount_cents: 8000,
                  ledger_kinds: [],
                }],
                withdrawals: [{
                  id: "saque-1",
                  external_reference: "saque-1",
                  asaas_transfer_id: "tra_1",
                  status: "done",
                  amount_cents: 6000,
                }],
              },
              error: null,
            });
          }
          if (name === "record_payment_divergences") {
            const rows = args.p_rows as Array<{ kind: string }>;
            assert(rows.some((row) => row.kind === "charge_status"));
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
  assertEquals(seen.length, 2);
  assert(seen.every((line) => line.startsWith("GET https://asaas.test/v3/")));
  assertEquals(calls, [
    "ledger_reconcile_snapshot",
    "record_payment_divergences",
  ]);
});
