import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  memberRefundActor,
  processMemberRefunds,
} from "./member_refund.ts";

type QueueRow = {
  id: string;
  charge_id: string;
  group_id: string;
  user_id: string;
  action: string;
  status: string;
  attempts: number;
  created_at: string;
};

type Charge = {
  id: string;
  amount_cents: number;
  charged_amount_cents: number | null;
  status: string;
  provider_ref: string;
  billing_type: string;
  custody_released_at: string | null;
  refund_requested_at: string | null;
};

type Store = {
  queue: QueueRow[];
  charges: Charge[];
  transitions: string[];
};

function adminFor(store: Store) {
  return {
    from(table: string) {
      return new Query(table, store);
    },
    rpc(name: string, args: Record<string, unknown>) {
      if (name === "apply_payment_transition") {
        const id = String(args.p_charge_id);
        const next = String(args.p_next_status);
        const charge = store.charges.find((item) => item.id === id);
        if (charge) charge.status = next;
        store.transitions.push(`${id}:${next}`);
        return Promise.resolve({
          data: {
            applied: true,
            status: next,
            paid_at: null,
            refunded_at: next === "refunded" ? "now" : null,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
}

class Query {
  #table: string;
  #store: Store;
  #filters: { column: string; op: string; value: unknown }[] = [];
  #limit = 50;
  #patch: Record<string, unknown> | null = null;

  constructor(table: string, store: Store) {
    this.#table = table;
    this.#store = store;
  }

  select(_columns: string) {
    return this;
  }

  eq(column: string, value: unknown) {
    this.#filters.push({ column, op: "eq", value });
    return this;
  }

  lt(column: string, value: unknown) {
    this.#filters.push({ column, op: "lt", value });
    return this;
  }

  order(_column: string, _opts: { ascending: boolean }) {
    return this;
  }

  limit(value: number) {
    this.#limit = value;
    return this;
  }

  update(patch: Record<string, unknown>) {
    this.#patch = patch;
    return this;
  }

  maybeSingle() {
    const rows = this.#rows();
    return Promise.resolve({ data: rows[0] ?? null, error: null });
  }

  then(
    resolve: (value: { data: unknown; error: null }) => unknown,
    reject?: (reason: unknown) => unknown,
  ) {
    return this.#run().then(resolve, reject);
  }

  #rows(): Record<string, unknown>[] {
    const source = this.#table === "member_refund_queue"
      ? this.#store.queue
      : this.#store.charges;
    return source.filter((row) => this.#match(row as Record<string, unknown>))
      .slice(0, this.#limit) as Record<string, unknown>[];
  }

  #match(row: Record<string, unknown>): boolean {
    return this.#filters.every((filter) => {
      const value = row[filter.column];
      if (filter.op === "lt") return Number(value) < Number(filter.value);
      return value === filter.value;
    });
  }

  #run(): Promise<{ data: unknown; error: null }> {
    if (!this.#patch) {
      return Promise.resolve({ data: this.#rows(), error: null });
    }
    const patch = this.#patch;
    const rows = this.#rows();
    for (const row of rows) Object.assign(row, patch);
    return Promise.resolve({ data: rows, error: null });
  }
}

function charge(partial: Partial<Charge> & { id: string }): Charge {
  return {
    amount_cents: 10000,
    charged_amount_cents: null,
    status: "paid",
    provider_ref: `CHAR_${partial.id}`,
    billing_type: "PIX",
    custody_released_at: null,
    refund_requested_at: "now",
    ...partial,
  };
}

function queued(chargeId: string, action: string): QueueRow {
  return {
    id: `q-${chargeId}`,
    charge_id: chargeId,
    group_id: "group-1",
    user_id: "user-1",
    action,
    status: "queued",
    attempts: 0,
    created_at: "2026-11-24T00:00:00Z",
  };
}

type Remote = { status: string };

function bank(options: {
  remote: Record<string, Remote>;
  failRefund?: boolean;
}) {
  const calls: string[] = [];
  let failRefund = options.failRefund ?? false;
  return {
    calls,
    release() {
      failRefund = false;
    },
    getPayment(id: string) {
      calls.push(`get:${id}`);
      return Promise.resolve({
        status: options.remote[id]?.status ?? "PAID",
      });
    },
    refund(id: string, cents: number) {
      calls.push(`refund:${cents}`);
      if (failRefund) return Promise.reject(new Error("PagBank 500"));
      options.remote[id] = { status: "REFUNDED" };
      return Promise.resolve({ id, status: "REFUNDED" });
    },
    cancelAuthorization(id: string, cents: number) {
      calls.push(`cancel:${cents}`);
      options.remote[id] = { status: "CANCELED" };
      return Promise.resolve({ id, status: "CANCELED" });
    },
    cancelPaymentConfirmed(id: string) {
      calls.push(`pix-cancel:${id}`);
      options.remote[id] = { status: "CANCELED" };
      return Promise.resolve(true);
    },
    releaseCustody() {
      calls.push("custody");
      return Promise.resolve();
    },
  };
}

Deno.test("Pix pago estorna e só então a cobrança fica refunded", async () => {
  const remote: Record<string, Remote> = { CHAR_pix: { status: "PAID" } };
  const store: Store = {
    queue: [queued("pix", "refund")],
    charges: [charge({ id: "pix", provider_ref: "CHAR_pix" })],
    transitions: [],
  };
  const client = bank({ remote });
  const result = await processMemberRefunds(adminFor(store), client);
  assertEquals(result, { done: 1, pending: 0 });
  assertEquals(client.calls.filter((call) => call.startsWith("refund:")), [
    "refund:10000",
  ]);
  assertEquals(store.charges[0].status, "refunded");
  assertEquals(store.queue[0].status, "done");
  assert(!client.calls.includes("custody"));
  const again = await processMemberRefunds(adminFor(store), client);
  assertEquals(again, { done: 0, pending: 0 });
  assertEquals(client.calls.filter((call) => call.startsWith("refund:")).length, 1);
});

Deno.test("cartão autorizado cancela sem captura", async () => {
  const remote: Record<string, Remote> = { CHAR_hold: { status: "AUTHORIZED" } };
  const store: Store = {
    queue: [queued("hold", "void")],
    charges: [charge({
      id: "hold",
      provider_ref: "CHAR_hold",
      billing_type: "CREDIT_CARD",
      status: "authorized",
      charged_amount_cents: 10640,
    })],
    transitions: [],
  };
  const client = bank({ remote });
  const result = await processMemberRefunds(adminFor(store), client);
  assertEquals(result.done, 1);
  assertEquals(client.calls.filter((call) => call.startsWith("cancel:")), [
    "cancel:10640",
  ]);
  assertEquals(store.transitions, ["hold:cancelled"]);
  assert(!client.calls.some((call) => call.startsWith("refund:")));
});

Deno.test("cartão capturado com custódia solta estorna o total com juros", async () => {
  const remote: Record<string, Remote> = { CHAR_cap: { status: "PAID" } };
  const store: Store = {
    queue: [queued("cap", "refund")],
    charges: [charge({
      id: "cap",
      provider_ref: "CHAR_cap",
      billing_type: "CREDIT_CARD",
      charged_amount_cents: 10640,
      custody_released_at: "2026-11-24T12:00:00Z",
    })],
    transitions: [],
  };
  const client = bank({ remote });
  await processMemberRefunds(adminFor(store), client);
  assertEquals(client.calls.filter((call) => call.startsWith("refund:")), [
    "refund:10640",
  ]);
  assertEquals(store.charges[0].status, "refunded");
  assert(!client.calls.includes("custody"));
});

Deno.test("falha da PagBank não marca refunded e a repetição estorna uma vez", async () => {
  const remote: Record<string, Remote> = { CHAR_pix: { status: "PAID" } };
  const store: Store = {
    queue: [queued("pix", "refund")],
    charges: [charge({ id: "pix", provider_ref: "CHAR_pix" })],
    transitions: [],
  };
  const client = bank({ remote, failRefund: true });
  const failed = await processMemberRefunds(adminFor(store), client);
  assertEquals(failed, { done: 0, pending: 1 });
  assertEquals(store.charges[0].status, "paid");
  assertEquals(store.queue[0].status, "queued");
  assertEquals(store.queue[0].attempts, 1);
  client.release();
  const retried = await processMemberRefunds(adminFor(store), client);
  assertEquals(retried, { done: 1, pending: 0 });
  assertEquals(client.calls.filter((call) => call.startsWith("refund:")), [
    "refund:10000",
    "refund:10000",
  ]);
  assertEquals(store.transitions, ["pix:refunded"]);
});

Deno.test("cobrança já estornada não chama a PagBank de novo", async () => {
  const remote: Record<string, Remote> = { CHAR_pix: { status: "REFUNDED" } };
  const store: Store = {
    queue: [queued("pix", "refund")],
    charges: [charge({ id: "pix", provider_ref: "CHAR_pix", status: "paid" })],
    transitions: [],
  };
  const client = bank({ remote });
  const result = await processMemberRefunds(adminFor(store), client);
  assertEquals(result.done, 1);
  assertEquals(client.calls.filter((call) => call.startsWith("refund:")), []);
  assertEquals(store.transitions, ["pix:refunded"]);
});

Deno.test("jogador só alcança a própria fila", async () => {
  const admin = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        maybeSingle() {
          if (table === "groups") {
            return Promise.resolve({
              data: { created_by: "org", venue_id: "venue" },
              error: null,
            });
          }
          if (table === "venues") {
            return Promise.resolve({
              data: { owner_id: "owner" },
              error: null,
            });
          }
          return Promise.resolve({
            data: { user_id: "player" },
            error: null,
          });
        },
      };
    },
  };
  assertEquals(await memberRefundActor(admin, "g", "org", false), {});
  assertEquals(
    await memberRefundActor(admin, "g", "player", false),
    { userId: "player" },
  );
  const stranger = {
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({ data: null, error: null });
        },
      };
    },
  };
  assertEquals(await memberRefundActor(stranger, "g", "other", false), null);
});
