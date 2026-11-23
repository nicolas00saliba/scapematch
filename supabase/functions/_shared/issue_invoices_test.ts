import { assertEquals } from "jsr:@std/assert";
import {
  invoiceAttemptLimit,
  invoiceEmissionEnabled,
  invoiceErrorRetryable,
  invoiceFailureReason,
  invoiceProcessingStaleMs,
  issuePaidInvoices,
  retryFailedInvoices,
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

Deno.test("webhook e settle ao mesmo tempo emitem cada nota uma vez", async () => {
  const state = { invoices: [] as Record<string, unknown>[] };
  let schedules = 0;
  const asaas = liveAsaas(() => {
    schedules += 1;
  });
  const admin = adminFor(state);
  await Promise.all([
    issuePaidInvoices(admin, charge, {
      sandbox: false,
      emissionEnabled: true,
      asaas,
    }),
    issuePaidInvoices(admin, charge, {
      sandbox: false,
      emissionEnabled: true,
      asaas,
    }),
  ]);
  assertEquals(schedules, 2);
  assertEquals(state.invoices.filter((row) => row.kind === "service").length, 1);
  assertEquals(
    state.invoices.filter((row) => row.kind === "commission").length,
    1,
  );
  assertEquals(
    state.invoices.every((row) => row.provider_invoice_id != null),
    true,
  );
});

Deno.test("processing velho reaproveita a nota e o recente não emite", async () => {
  const stale = new Date(Date.now() - invoiceProcessingStaleMs - 1000).toISOString();
  const state = {
    invoices: [{
      id: "nota-velha",
      payment_charge_id: "charge-1",
      kind: "commission",
      status: "processing",
      provider_invoice_id: null,
      attempt_count: 1,
      updated_at: stale,
      error_message: null,
    }, {
      id: "nota-nova",
      payment_charge_id: "charge-1",
      kind: "service",
      status: "processing",
      provider_invoice_id: null,
      attempt_count: 1,
      updated_at: new Date().toISOString(),
      error_message: null,
    }],
  };
  let schedules = 0;
  await issuePaidInvoices(adminFor(state), charge, {
    sandbox: false,
    emissionEnabled: true,
    asaas: liveAsaas(() => {
      schedules += 1;
    }, {
      "commission:charge-1": { id: "inv_antiga", status: "AUTHORIZED" },
    }),
  });
  const commission = state.invoices.find((row) => row.kind === "commission");
  const service = state.invoices.find((row) => row.kind === "service");
  assertEquals(schedules, 0);
  assertEquals(commission?.provider_invoice_id, "inv_antiga");
  assertEquals(commission?.status, "authorized");
  assertEquals(service?.status, "processing");
  assertEquals(service?.provider_invoice_id, null);
});

Deno.test("erro sem certificado volta a emitir até o limite", async () => {
  const reason = invoiceFailureReason(new Error(
    'Asaas 400 {"errors":[{"code":"invalid_object","description":"Certificado digital ausente"}]}',
  ));
  assertEquals(reason, "sem_certificado");
  assertEquals(invoiceErrorRetryable(reason), true);
  assertEquals(invoiceErrorRetryable("internal_error:abc"), false);

  const failing = { invoices: [] as Record<string, unknown>[] };
  await issuePaidInvoices(adminFor(failing), charge, {
    sandbox: false,
    emissionEnabled: true,
    asaas: failingAsaas(new Error(
      'Asaas 400 {"errors":[{"code":"invalid_object","description":"Certificado digital ausente"}]}',
    )),
  });
  assertEquals(failing.invoices.every((row) => row.status === "error"), true);
  assertEquals(
    failing.invoices.every((row) => row.error_message === "sem_certificado"),
    true,
  );
  assertEquals(failing.invoices.every((row) => row.attempt_count === 1), true);

  let schedules = 0;
  const state = {
    invoices: [{
      id: "nota-comissao",
      payment_charge_id: "charge-1",
      kind: "commission",
      status: "error",
      provider_invoice_id: null,
      attempt_count: 1,
      updated_at: "2026-11-13T12:00:00.000Z",
      error_message: "sem_certificado",
    }, {
      id: "nota-servico",
      payment_charge_id: "charge-1",
      kind: "service",
      status: "authorized",
      provider_invoice_id: "inv_servico",
      attempt_count: 1,
      error_message: null,
    }],
    charges: { "charge-1": { ...charge } },
  };
  const retried = await retryFailedInvoices(adminFor(state), {
    sandbox: false,
    emissionEnabled: true,
    asaas: liveAsaas(() => {
      schedules += 1;
    }),
  });
  const commission = state.invoices.find((row) => row.kind === "commission");
  assertEquals(retried, 1);
  assertEquals(schedules, 1);
  assertEquals(commission?.status, "authorized");
  assertEquals(commission?.attempt_count, 2);

  const exhausted = {
    invoices: [{
      id: "nota-limite",
      payment_charge_id: "charge-1",
      kind: "commission",
      status: "error",
      provider_invoice_id: null,
      attempt_count: invoiceAttemptLimit,
      error_message: "asaas_unavailable",
    }],
    charges: { "charge-1": { ...charge } },
  };
  let extra = 0;
  const again = await retryFailedInvoices(adminFor(exhausted), {
    sandbox: false,
    emissionEnabled: true,
    asaas: liveAsaas(() => {
      extra += 1;
    }),
  });
  assertEquals(again, 0);
  assertEquals(extra, 0);
  assertEquals(exhausted.invoices[0]?.status, "error");

  const off = await retryFailedInvoices(adminFor(state), {
    sandbox: false,
    emissionEnabled: false,
    asaas: liveAsaas(() => {
      extra += 1;
    }),
  });
  assertEquals(off, 0);
});

function liveAsaas(
  onSchedule: () => void,
  existing: Record<string, { id: string; status: string }> = {},
) {
  let created = 0;
  const asaas = {
    findInvoiceByReference(reference: string) {
      return Promise.resolve(existing[reference] ?? null);
    },
    scheduleInvoice() {
      onSchedule();
      created += 1;
      return Promise.resolve({ id: `inv_${created}`, status: "SCHEDULED" });
    },
    authorizeInvoice(id: string) {
      return Promise.resolve({ id, status: "AUTHORIZED" });
    },
    getInvoice(id: string) {
      return Promise.resolve({
        id,
        status: "AUTHORIZED",
        number: "15",
        pdfUrl: "https://asaas.com/nota.pdf",
        xmlUrl: "https://asaas.com/nota.xml",
      });
    },
    createCustomer() {
      return Promise.resolve({ id: "cus_1" });
    },
    withKey() {
      return asaas;
    },
  };
  return asaas as never;
}

function failingAsaas(error: Error) {
  const asaas = {
    findInvoiceByReference() {
      return Promise.resolve(null);
    },
    scheduleInvoice() {
      throw error;
    },
    authorizeInvoice() {
      throw error;
    },
    getInvoice() {
      throw error;
    },
    createCustomer() {
      return Promise.resolve({ id: "cus_1" });
    },
    withKey() {
      return asaas;
    },
  };
  return asaas as never;
}

function asaasSpy(calls: string[]): never {
  return new Proxy({}, {
    get(_target, prop) {
      calls.push(String(prop));
      throw new Error("asaas chamado");
    },
  }) as never;
}

function adminFor(state: {
  invoices: Record<string, unknown>[];
  charges?: Record<string, Record<string, unknown>>;
}) {
  return {
    auth: {
      admin: {
        getUserById() {
          return Promise.resolve({ data: { user: { email: "ana@example.com" } } });
        },
      },
    },
    rpc() {
      return Promise.resolve({ data: "chave-subconta", error: null });
    },
    from(table: string) {
      let mode = "select";
      const filters: Record<string, unknown> = {};
      const nulls: Record<string, unknown> = {};
      const below: Record<string, unknown> = {};
      let patch: Record<string, unknown> | null = null;
      const api = {
        select() {
          if (mode !== "update") mode = "select";
          return api;
        },
        eq(column: string, value: unknown) {
          filters[column] = value;
          return api;
        },
        is(column: string, value: unknown) {
          nulls[column] = value;
          return api;
        },
        lt(column: string, value: unknown) {
          below[column] = value;
          return api;
        },
        limit() {
          return api;
        },
        neq() {
          return api;
        },
        insert(row: Record<string, unknown>) {
          if (table !== "fiscal_invoices") {
            return Promise.resolve({ data: [row], error: null });
          }
          const duplicate = state.invoices.some((item) =>
            item.payment_charge_id === row.payment_charge_id &&
            item.kind === row.kind
          );
          if (duplicate) {
            return Promise.resolve({ data: null, error: { code: "23505" } });
          }
          state.invoices.push(row);
          return Promise.resolve({ data: [row], error: null });
        },
        update(row: Record<string, unknown>) {
          mode = "update";
          patch = row;
          return api;
        },
        maybeSingle() {
          if (table === "payment_charges") {
            const id = String(filters.id ?? "");
            return Promise.resolve({
              data: state.charges?.[id] ?? null,
              error: null,
            });
          }
          return Promise.resolve({ data: single(table), error: null });
        },
        then(resolve: (value: unknown) => void) {
          if (mode === "update") {
            const found = state.invoices.filter((item) =>
              matches(item, filters, nulls, below)
            );
            if (patch) {
              for (const item of found) Object.assign(item, patch);
            }
            resolve({
              data: found.map((item) => ({ id: item.id })),
              error: null,
            });
            return;
          }
          if (table === "group_members") {
            resolve({ count: 2, data: null, error: null });
            return;
          }
          if (table === "fiscal_invoices") {
            resolve({
              data: state.invoices.filter((item) =>
                matches(item, filters, nulls, below)
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

function matches(
  item: Record<string, unknown>,
  filters: Record<string, unknown>,
  nulls: Record<string, unknown>,
  below: Record<string, unknown>,
): boolean {
  for (const [column, value] of Object.entries(filters)) {
    if (item[column] !== value) return false;
  }
  for (const [column, value] of Object.entries(nulls)) {
    if (value === null && item[column] != null) return false;
  }
  for (const [column, value] of Object.entries(below)) {
    const current = item[column];
    if (typeof value === "number") {
      const amount = typeof current === "number" ? current : 0;
      if (!(amount < value)) return false;
      continue;
    }
    if (String(current ?? "") >= String(value)) return false;
  }
  return true;
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
  if (table === "profiles") {
    return { display_name: "Ana", cpf: "52998224725" };
  }
  return null;
}
