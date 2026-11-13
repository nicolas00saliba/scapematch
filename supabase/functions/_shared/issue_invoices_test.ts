import { assertEquals } from "jsr:@std/assert";
import {
  invoiceEmissionEnabled,
  issuePaidInvoices,
  shouldEmitInvoice,
} from "./issue_invoices.ts";

const charge = {
  id: "charge-1",
  group_id: "group-1",
  user_id: "user-1",
  venue_id: "venue-1",
  amount_cents: 10000,
  commission_bps: 2500,
};

Deno.test("a emissão só liga com o valor on", () => {
  assertEquals(invoiceEmissionEnabled({ get: () => undefined }), false);
  assertEquals(invoiceEmissionEnabled({ get: () => "" }), false);
  assertEquals(invoiceEmissionEnabled({ get: () => "true" }), false);
  assertEquals(invoiceEmissionEnabled({ get: () => "1" }), false);
  assertEquals(invoiceEmissionEnabled({ get: () => "on" }), true);
  assertEquals(invoiceEmissionEnabled({ get: () => " ON " }), true);
  assertEquals(
    invoiceEmissionEnabled({
      get() {
        throw new Error("NotCapable");
      },
    }),
    false,
  );
  assertEquals(
    shouldEmitInvoice({
      status: "scheduled",
      sandbox: false,
      emissionEnabled: false,
      hasClient: true,
    }),
    false,
  );
  assertEquals(
    shouldEmitInvoice({
      status: "scheduled",
      sandbox: true,
      emissionEnabled: true,
      hasClient: true,
    }),
    false,
  );
  assertEquals(
    shouldEmitInvoice({
      status: "scheduled",
      sandbox: false,
      emissionEnabled: true,
      hasClient: true,
    }),
    true,
  );
});

Deno.test("produção desligada grava a nota e não chama o Asaas", async () => {
  const state = { invoices: [] as Record<string, unknown>[] };
  const calls: string[] = [];
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: false,
    emissionEnabled: false,
    asaas: asaasSpy(calls),
  });
  assertEquals(calls, []);
  assertEquals(state.invoices.map((row) => row.kind), ["service", "commission"]);
  assertEquals(state.invoices.every((row) => row.status === "scheduled"), true);
  assertEquals(
    state.invoices.every((row) => row.provider_invoice_id == null),
    true,
  );
  assertEquals(state.invoices.every((row) => row.error_message == null), true);
});

Deno.test("nota já gravada continua pendente enquanto a chave está off", async () => {
  const state = {
    invoices: [{
      id: "nota-1",
      payment_charge_id: "charge-1",
      kind: "commission",
      status: "scheduled",
      provider_invoice_id: null,
    }, {
      id: "nota-2",
      payment_charge_id: "charge-1",
      kind: "service",
      status: "scheduled",
      provider_invoice_id: null,
    }],
  };
  const calls: string[] = [];
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: false,
    emissionEnabled: false,
    asaas: asaasSpy(calls),
  });
  assertEquals(calls, []);
  assertEquals(state.invoices.length, 2);
  assertEquals(state.invoices.every((row) => row.status === "scheduled"), true);
});

Deno.test("com a chave on a falha da nota não rejeita a cobrança", async () => {
  const state = { invoices: [] as Record<string, unknown>[] };
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: false,
    emissionEnabled: true,
    asaas: asaasSpy([]),
  });
  assertEquals(state.invoices.map((row) => row.status), ["error", "error"]);
  assertEquals(
    state.invoices.every((row) => typeof row.error_message === "string"),
    true,
  );
});

Deno.test("chave on emite a nota que estava scheduled", async () => {
  const state = {
    invoices: [{
      id: "nota-comissao",
      payment_charge_id: "charge-1",
      kind: "commission",
      status: "scheduled",
      provider_invoice_id: null,
    }, {
      id: "nota-servico",
      payment_charge_id: "charge-1",
      kind: "service",
      status: "authorized",
      provider_invoice_id: "inv_servico",
    }],
  };
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: false,
    emissionEnabled: true,
    asaas: asaasSpy([]),
  });
  const commission = state.invoices.find((row) => row.kind === "commission");
  const service = state.invoices.find((row) => row.kind === "service");
  assertEquals(commission?.status, "error");
  assertEquals(service?.status, "authorized");
  assertEquals(state.invoices.length, 2);
});

Deno.test("sandbox continua simulado mesmo com a chave ligada", async () => {
  const state = { invoices: [] as Record<string, unknown>[] };
  const calls: string[] = [];
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: true,
    emissionEnabled: true,
    asaas: asaasSpy(calls),
  });
  assertEquals(calls, []);
  assertEquals(state.invoices.every((row) => row.status === "simulated"), true);
});

function asaasSpy(calls: string[]): never {
  return new Proxy({}, {
    get(_target, prop) {
      calls.push(String(prop));
      throw new Error("asaas chamado");
    },
  }) as never;
}

function adminFor(state: { invoices: Record<string, unknown>[] }) {
  return {
    from(table: string) {
      let mode = "select";
      const filters: Record<string, unknown> = {};
      let patch: Record<string, unknown> | null = null;
      const api = {
        select() {
          mode = "select";
          return api;
        },
        eq(column: string, value: unknown) {
          filters[column] = value;
          return api;
        },
        neq() {
          return api;
        },
        insert(row: Record<string, unknown>) {
          state.invoices.push(row);
          return Promise.resolve({ error: null });
        },
        update(row: Record<string, unknown>) {
          mode = "update";
          patch = row;
          return api;
        },
        maybeSingle() {
          return Promise.resolve({ data: single(table), error: null });
        },
        then(resolve: (value: unknown) => void) {
          if (mode === "update") {
            const found = state.invoices.find((item) => item.id === filters.id);
            if (found && patch) Object.assign(found, patch);
            resolve({ error: null });
            return;
          }
          if (table === "group_members") {
            resolve({ count: 2, data: null, error: null });
            return;
          }
          if (table === "fiscal_invoices") {
            resolve({
              data: state.invoices.filter((item) =>
                item.payment_charge_id === filters.payment_charge_id
              ),
              error: null,
            });
            return;
          }
          resolve({ data: null, error: null });
        },
      };
      return api;
    },
  };
}

function single(table: string): Record<string, unknown> | null {
  if (table === "groups") {
    return {
      confirmed_at: "2026-11-01T00:00:00Z",
      cancelled_at: null,
      closed_at: null,
      closes_at: null,
      total_spots: 6,
      minimum_spots: 2,
    };
  }
  if (table === "venues") {
    return {
      name: "Casa",
      owner_id: "owner-1",
      document_kind: "cnpj",
      document_number: "70100608000173",
    };
  }
  if (table === "venue_fiscal") {
    return {
      municipal_inscription: "123",
      service_code: "12.08",
      service_name: "Lazer",
      iss_rate: 2,
    };
  }
  if (table === "profiles") return { display_name: "Ana" };
  return null;
}
