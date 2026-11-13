import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { createCharge } from "./index.ts";

const groupId = "11111111-1111-1111-1111-111111111111";
const userId = "22222222-2222-2222-2222-222222222222";
const venueId = "33333333-3333-3333-3333-333333333333";
const cardId = "55555555-5555-5555-5555-555555555555";
const leaseMs = 2 * 60 * 1000;

type Charge = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  billing_type: string;
  status: string;
  provider_ref: string | null;
  idempotency_key: string;
  wallet_id: string;
  commission_bps: number;
  reserved_at: string;
  attempt_id: string | null;
  qr_code: string | null;
  qr_code_base64: string | null;
};

type Payment = {
  id: string;
  status: string;
  billingType: string;
  externalReference: string;
  customer: string;
  value: number;
  split: { walletId: string; fixedValue: number }[];
  deleted?: boolean;
  deleteAsPending?: boolean;
};

type Store = {
  charges: Charge[];
  orphans: { provider_ref: string; reason: string }[];
  payments: Payment[];
  calls: string[];
  member: string;
  closed: boolean;
  detachMissing?: boolean;
  releaseExpiredError?: boolean;
};

function expiredAt(): string {
  return new Date(Date.now() - leaseMs - 1000).toISOString();
}

function freshAt(): string {
  return new Date().toISOString();
}

function leaseExpired(row: Charge): boolean {
  return Date.now() - Date.parse(row.reserved_at) >= leaseMs;
}

function makeStore(seed?: Partial<Charge>): Store {
  const store: Store = {
    charges: [],
    orphans: [],
    payments: [],
    calls: [],
    member: "pending",
    closed: false,
  };
  if (seed) {
    store.charges.push({
      id: "44444444-4444-4444-4444-444444444444",
      group_id: groupId,
      user_id: userId,
      venue_id: venueId,
      amount_cents: 10000,
      billing_type: "PIX",
      status: "creating",
      provider_ref: null,
      idempotency_key: "idem-seed-1",
      wallet_id: "wal_house",
      commission_bps: 1000,
      reserved_at: expiredAt(),
      attempt_id: crypto.randomUUID(),
      qr_code: null,
      qr_code_base64: null,
      ...seed,
    });
  }
  return store;
}

function adminFor(store: Store) {
  let chain = Promise.resolve();
  const lock = <T>(fn: () => T): Promise<T> => {
    const run = chain.then(fn, fn);
    chain = run.then(() => undefined, () => undefined);
    return run;
  };
  const byId = (id: string) => store.charges.find((row) => row.id === id);

  const reserved = (row: Charge, inserted: boolean) => ({
    id: row.id,
    status: row.status,
    provider_ref: row.provider_ref,
    billing_type: row.billing_type,
    amount_cents: row.amount_cents,
    inserted,
    reserved_at: row.reserved_at,
    attempt_id: row.attempt_id,
    idempotency_key: row.idempotency_key,
    lease_expired: !inserted && row.provider_ref === null &&
      row.status === "creating" && leaseExpired(row),
  });

  const reserve = (
    billing: string,
    args: Record<string, unknown>,
  ) => {
    const group = String(args.p_group_id);
    const user = String(args.p_user_id);
    let row = store.charges.find((item) =>
      item.group_id === group && item.user_id === user
    );
    let inserted = false;
    if (!row) {
      row = {
        id: crypto.randomUUID(),
        group_id: group,
        user_id: user,
        venue_id: String(args.p_venue_id),
        amount_cents: Number(args.p_amount_cents),
        billing_type: billing,
        status: "creating",
        provider_ref: null,
        idempotency_key: String(args.p_idempotency_key),
        wallet_id: String(args.p_wallet_id),
        commission_bps: Number(args.p_commission_bps),
        reserved_at: freshAt(),
        attempt_id: crypto.randomUUID(),
        qr_code: null,
        qr_code_base64: null,
      };
      store.charges.push(row);
      inserted = true;
    }
    return reserved(row, inserted);
  };

  return {
    from(table: string) {
      const filters: { col: string; op: "eq" | "neq"; value: unknown }[] = [];
      let mode: "select" | "update" = "select";
      let patch: Record<string, unknown> = {};
      let head = false;
      let returning = false;
      const rows = () => {
        if (table === "groups") {
          return [{
            id: groupId,
            venue_id: venueId,
            price_cents: 10000,
            cancelled_at: null,
            closed_at: store.closed ? freshAt() : null,
            starts_at: new Date(Date.now() + 86_400_000).toISOString(),
            total_spots: 8,
            minimum_spots: store.closed ? 1 : 4,
          }];
        }
        if (table === "venues") {
          return [{
            id: venueId,
            name: "Casa",
            asaas_wallet_id: "wal_house",
            status: "approved",
          }];
        }
        if (table === "profiles") {
          return [{
            id: userId,
            display_name: "Jogador",
            asaas_customer_id: "cus_1",
            cpf: "52998224725",
          }];
        }
        if (table === "group_members") {
          return [{
            id: "66666666-6666-6666-6666-666666666666",
            group_id: groupId,
            user_id: userId,
            attendance: "confirmed",
            payment_status: store.member,
          }];
        }
        return store.charges;
      };
      const matched = () =>
        rows().filter((row) =>
          filters.every((filter) => {
            const value = (row as Record<string, unknown>)[filter.col];
            return filter.op === "eq"
              ? value === filter.value
              : value !== filter.value;
          })
        );
      const self = {
        select(_cols: string, opts?: { head?: boolean }) {
          head = Boolean(opts?.head);
          if (mode === "update") returning = true;
          return self;
        },
        update(next: Record<string, unknown>) {
          mode = "update";
          patch = next;
          return self;
        },
        eq(col: string, value: unknown) {
          filters.push({ col, op: "eq", value });
          return self;
        },
        neq(col: string, value: unknown) {
          filters.push({ col, op: "neq", value });
          return self;
        },
        maybeSingle() {
          return Promise.resolve({ data: matched()[0] ?? null, error: null });
        },
        then(
          resolve: (value: unknown) => void,
          reject?: (error: unknown) => void,
        ) {
          try {
            if (mode === "update") {
              const hit = matched();
              for (const row of hit) Object.assign(row, patch);
              resolve({ data: returning ? hit : null, error: null });
              return;
            }
            resolve({
              data: head ? null : matched(),
              error: null,
              count: matched().length,
            });
          } catch (error) {
            reject?.(error);
          }
        },
      };
      return self;
    },
    rpc(name: string, args: Record<string, unknown>) {
      return lock(() => {
        if (name === "commission_bps_for_venue") {
          return { data: 1000, error: null };
        }
        if (name === "cap_point_redemption") {
          // A corrida não resgata. A regra de verdade está em cap_point_redemption no SQL.
          return { data: Number(args.p_points ?? 0), error: null };
        }
        if (name === "load_owned_card") {
          return {
            data: {
              id: cardId,
              token: "tok_test_1234",
              last4: "4242",
              brand: "VISA",
            },
            error: null,
          };
        }
        if (name === "reserve_pix_charge") {
          return { data: reserve("PIX", args), error: null };
        }
        if (name === "reserve_card_charge") {
          return { data: reserve("CREDIT_CARD", args), error: null };
        }
        if (name === "claim_expired_pix_reservation") {
          const row = byId(String(args.p_charge_id));
          if (
            row && row.status === "creating" && row.provider_ref === null &&
            leaseExpired(row)
          ) {
            row.attempt_id = crypto.randomUUID();
            row.reserved_at = freshAt();
            return { data: row.attempt_id, error: null };
          }
          return { data: null, error: null };
        }
        if (name === "attach_pix_provider") {
          const row = byId(String(args.p_charge_id));
          const attempt = args.p_attempt_id;
          if (
            row && row.provider_ref === null && row.attempt_id === attempt
          ) {
            row.provider_ref = String(args.p_provider_ref);
            return { data: row.provider_ref, error: null };
          }
          return { data: row?.provider_ref ?? null, error: null };
        }
        if (name === "release_pix_reservation") {
          const row = byId(String(args.p_charge_id));
          if (
            row && row.status === "creating" && row.provider_ref === null &&
            row.attempt_id === args.p_attempt_id
          ) {
            store.charges = store.charges.filter((item) => item.id !== row.id);
            return { data: true, error: null };
          }
          return { data: false, error: null };
        }
        if (name === "release_expired_pix_reservation") {
          if (store.releaseExpiredError) {
            return {
              data: null,
              error: { code: "23503", message: "venue_credit_applications_payment_charge_id_fkey" },
            };
          }
          const row = byId(String(args.p_charge_id));
          if (
            row && row.status === "creating" && row.provider_ref === null &&
            row.attempt_id === args.p_attempt_id && leaseExpired(row)
          ) {
            store.charges = store.charges.filter((item) => item.id !== row.id);
            return { data: true, error: null };
          }
          return { data: false, error: null };
        }
        if (name === "clear_pix_provider_ref") {
          const row = byId(String(args.p_charge_id));
          if (
            row && row.provider_ref === args.p_provider_ref &&
            row.billing_type === "PIX"
          ) {
            row.provider_ref = null;
            row.billing_type = "CREDIT_CARD";
            row.status = "creating";
            row.qr_code = null;
            row.qr_code_base64 = null;
            row.attempt_id = crypto.randomUUID();
            row.reserved_at = freshAt();
            return { data: row.attempt_id, error: null };
          }
          return { data: null, error: null };
        }
        if (name === "detach_gone_pix") {
          if (store.detachMissing) {
            return { data: null, error: { code: "PGRST202" } };
          }
          const row = byId(String(args.p_charge_id));
          if (
            row && row.provider_ref === args.p_provider_ref &&
            row.billing_type === "PIX" &&
            (row.status === "pending" || row.status === "creating")
          ) {
            row.provider_ref = null;
            row.qr_code = null;
            row.qr_code_base64 = null;
            row.status = "creating";
            row.attempt_id = crypto.randomUUID();
            row.reserved_at = expiredAt();
            return { data: row.attempt_id, error: null };
          }
          return { data: null, error: null };
        }
        if (name === "apply_payment_transition") {
          const row = byId(String(args.p_charge_id));
          if (!row) return { data: null, error: { code: "P0002" } };
          row.status = String(args.p_next_status);
          store.calls.push(`transition ${row.status}`);
          store.member = row.status === "paid"
            ? "paid"
            : row.status === "authorized"
            ? "reserved"
            : row.status === "refunded" || row.status === "cancelled" ||
                row.status === "failed"
            ? "released"
            : "pending";
          return {
            data: {
              applied: true,
              status: row.status,
              paid_at: row.status === "paid" ? freshAt() : null,
              refunded_at: null,
            },
            error: null,
          };
        }
        if (name === "record_orphan_payment") {
          store.orphans.push({
            provider_ref: String(args.p_provider_ref),
            reason: String(args.p_reason),
          });
          return { data: crypto.randomUUID(), error: null };
        }
        if (name === "delete_compensated_charge") {
          const row = byId(String(args.p_charge_id));
          if (
            row && row.status === "cancelled" &&
            row.provider_ref === args.p_provider_ref &&
            row.attempt_id === args.p_attempt_id
          ) {
            store.charges = store.charges.filter((item) => item.id !== row.id);
            return { data: true, error: null };
          }
          return { data: false, error: null };
        }
        return { data: null, error: { code: "42883" } };
      });
    },
  };
}

function paymentBody(payment: Payment): Record<string, unknown> {
  return {
    id: payment.id,
    status: payment.status,
    billingType: payment.billingType,
    externalReference: payment.externalReference,
    customer: payment.customer,
    value: payment.value,
    split: payment.split,
    deleted: payment.deleted === true,
  };
}

function providerFor(
  store: Store,
  hooks: {
    onPixPost?: (payment: Payment) => Promise<Payment | Response>;
    onCardPost?: (payment: Payment) => Promise<Payment | Response>;
    onCapture?: () => Promise<Response | null>;
    onRefund?: () => Promise<Response | null>;
  },
) {
  let seq = 0;
  const fetchFn = async (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    store.calls.push(`${method} ${url}`);
    if (url.includes("/customers/")) {
      return new Response(
        JSON.stringify({ id: "cus_1", cpfCnpj: "52998224725" }),
        {
          status: 200,
        },
      );
    }
    if (
      method === "GET" && url.includes("/payments?") &&
      url.includes("externalReference=")
    ) {
      const reference = new URL(url).searchParams.get("externalReference");
      const rows = store.payments.filter((item) =>
        item.externalReference === reference
      );
      return new Response(JSON.stringify({ data: rows }), { status: 200 });
    }
    if (method === "GET" && url.includes("/pixQrCode")) {
      return new Response(
        JSON.stringify({ payload: "qr", encodedImage: "img" }),
        { status: 200 },
      );
    }
    const paymentMatch = url.match(
      /\/payments\/([^/?]+)(?:\/(refund|captureAuthorizedPayment))?$/,
    );
    if (paymentMatch && method === "GET") {
      const payment = store.payments.find((item) =>
        item.id === paymentMatch[1]
      );
      if (!payment || payment.status === "DELETED") {
        return new Response("não", { status: 404 });
      }
      return new Response(JSON.stringify(paymentBody(payment)), {
        status: 200,
      });
    }
    if (paymentMatch && method === "DELETE") {
      const payment = store.payments.find((item) =>
        item.id === paymentMatch[1]
      );
      if (!payment) return new Response("não", { status: 404 });
      if (payment.deleteAsPending) {
        payment.deleted = true;
        payment.status = "PENDING";
        return new Response(
          JSON.stringify({
            id: payment.id,
            status: "PENDING",
            deleted: true,
            billingType: payment.billingType,
          }),
          { status: 200 },
        );
      }
      payment.status = "DELETED";
      return new Response(
        JSON.stringify({ id: payment.id, status: "DELETED" }),
        {
          status: 200,
        },
      );
    }
    if (paymentMatch?.[2] === "refund" && method === "POST") {
      if (hooks.onRefund) {
        const custom = await hooks.onRefund();
        if (custom) return custom;
      }
      const payment = store.payments.find((item) =>
        item.id === paymentMatch[1]
      );
      if (!payment) return new Response("não", { status: 404 });
      payment.status = "REFUNDED";
      return new Response(JSON.stringify(paymentBody(payment)), {
        status: 200,
      });
    }
    if (paymentMatch?.[2] === "captureAuthorizedPayment" && method === "POST") {
      if (hooks.onCapture) {
        const custom = await hooks.onCapture();
        if (custom) return custom;
      }
      const payment = store.payments.find((item) =>
        item.id === paymentMatch[1]
      );
      if (!payment) return new Response("não", { status: 404 });
      payment.status = "CONFIRMED";
      return new Response(JSON.stringify(paymentBody(payment)), {
        status: 200,
      });
    }
    if (method === "POST" && url.endsWith("/payments")) {
      const body = JSON.parse(String(init?.body ?? "{}")) as {
        billingType?: string;
        externalReference?: string;
      };
      seq += 1;
      const payment: Payment = {
        id: `pay_${seq}`,
        status: body.billingType === "CREDIT_CARD" ? "AUTHORIZED" : "PENDING",
        billingType: body.billingType ?? "PIX",
        externalReference: body.externalReference ?? "",
        customer: "cus_1",
        value: 100,
        split: [{ walletId: "wal_house", fixedValue: 90 }],
      };
      if (body.billingType === "PIX" && hooks.onPixPost) {
        const held = await hooks.onPixPost(payment);
        if (held instanceof Response) return held;
        if (!store.payments.includes(held)) store.payments.push(held);
        return new Response(JSON.stringify(paymentBody(held)), { status: 200 });
      }
      if (body.billingType === "CREDIT_CARD" && hooks.onCardPost) {
        const held = await hooks.onCardPost(payment);
        if (held instanceof Response) return held;
        if (!store.payments.includes(held)) store.payments.push(held);
        return new Response(JSON.stringify(paymentBody(held)), { status: 200 });
      }
      store.payments.push(payment);
      return new Response(JSON.stringify(paymentBody(payment)), {
        status: 200,
      });
    }
    return new Response("não", { status: 500 });
  };
  return new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
    () => Promise.resolve(),
  );
}

function request(billing: string, key: string): Request {
  return new Request("https://example.test/create-charge", {
    method: "POST",
    body: JSON.stringify({
      group_id: groupId,
      billing_type: billing,
      idempotency_key: key,
      saved_card_id: cardId,
    }),
  });
}

function chargeRuntime(store: Store, asaas: AsaasProvider) {
  return {
    user: { id: userId, email: "jogador@example.com" },
    admin: adminFor(store),
    asaas,
  };
}

Deno.test("Pix e Pix: a tentativa que perde cancela o próprio pagamento", async () => {
  const store = makeStore();
  let releaseFirst: () => void = () => undefined;
  const gate = new Promise<void>((resolve) => {
    releaseFirst = resolve;
  });
  let started: () => void = () => undefined;
  const startedGate = new Promise<void>((resolve) => {
    started = resolve;
  });
  let pixPosts = 0;
  const asaas = providerFor(store, {
    onPixPost: async (payment) => {
      pixPosts += 1;
      if (pixPosts === 1) {
        const row = store.charges[0];
        if (row) row.reserved_at = expiredAt();
        started();
        await gate;
      }
      return payment;
    },
  });
  const runtime = chargeRuntime(store, asaas);
  const first = createCharge(request("PIX", "idem-pix-a1"), runtime);
  await startedGate;
  const second = await createCharge(request("PIX", "idem-pix-b1"), runtime);
  releaseFirst();
  const loser = await first;
  const winner = await second.json();
  assertEquals(loser.status, 409);
  assertEquals(winner.status, "pending");
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, winner.provider_ref);
  const live = store.payments.filter((item) => item.status !== "DELETED");
  assertEquals(live.length, 1);
  assertEquals(live[0].id, winner.provider_ref);
  assertEquals(store.orphans.length, 0);
  assert(store.payments.some((item) => item.status === "DELETED"));
});

Deno.test("Pix e cartão: o cartão é aceito antes de apagar o Pix", async () => {
  const store = makeStore();
  let releaseFirst: () => void = () => undefined;
  const gate = new Promise<void>((resolve) => {
    releaseFirst = resolve;
  });
  let started: () => void = () => undefined;
  const startedGate = new Promise<void>((resolve) => {
    started = resolve;
  });
  const asaas = providerFor(store, {
    onPixPost: async (payment) => {
      store.payments.push(payment);
      const row = store.charges[0];
      if (row) row.reserved_at = expiredAt();
      started();
      await gate;
      return payment;
    },
  });
  const runtime = chargeRuntime(store, asaas);
  const pix = createCharge(request("PIX", "idem-pix-card"), runtime);
  await startedGate;
  const card = await createCharge(
    request("CREDIT_CARD", "idem-card-px"),
    runtime,
  );
  releaseFirst();
  const pixResult = await pix;
  const cardBody = await card.json();
  assertEquals(pixResult.status, 409);
  assertEquals(card.status, 200);
  assertEquals(cardBody.billing_type, "CREDIT_CARD");
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].billing_type, "CREDIT_CARD");
  assertEquals(store.charges[0].provider_ref, cardBody.provider_ref);
  const pixPayment = store.payments.find((item) => item.billingType === "PIX");
  assertEquals(pixPayment?.status, "DELETED");
  const searches = store.calls
    .map((call, index) => ({ call, index }))
    .filter((item) => item.call.includes("externalReference="));
  const posts = store.calls
    .map((call, index) => ({ call, index }))
    .filter((item) =>
      item.call.startsWith("POST ") && item.call.endsWith("/payments")
    );
  const deleted = store.calls.findIndex((call) => call.startsWith("DELETE "));
  assert(searches.length >= 2);
  assert(posts.length >= 2);
  assert(posts[1].index > posts[0].index);
  assert(searches[1].index > posts[1].index);
  assert(deleted > searches[1].index);
  assertEquals(store.orphans.length, 0);
});

Deno.test("cartão e cartão: captura já feita vira estorno, não cancelAuthorization", async () => {
  const store = makeStore({
    billing_type: "CREDIT_CARD",
    idempotency_key: "idem-card-seed",
  });
  let releaseFirst: () => void = () => undefined;
  const gate = new Promise<void>((resolve) => {
    releaseFirst = resolve;
  });
  let started: () => void = () => undefined;
  const startedGate = new Promise<void>((resolve) => {
    started = resolve;
  });
  let cardPosts = 0;
  const asaas = providerFor(store, {
    onCardPost: async (payment) => {
      cardPosts += 1;
      if (cardPosts === 1) {
        const row = store.charges.find((item) => item.provider_ref === null);
        if (row) row.reserved_at = expiredAt();
        started();
        await gate;
        return { ...payment, status: "CONFIRMED" };
      }
      return payment;
    },
  });
  const runtime = chargeRuntime(store, asaas);
  const first = createCharge(request("CREDIT_CARD", "idem-card-a"), runtime);
  await startedGate;
  const second = await createCharge(
    request("CREDIT_CARD", "idem-card-b"),
    runtime,
  );
  releaseFirst();
  const loser = await first;
  const winner = await second.json();
  assertEquals(loser.status, 409);
  assertEquals(second.status, 200);
  assertEquals(winner.status, "authorized");
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, winner.provider_ref);
  const captured = store.payments.find((item) => item.status === "REFUNDED");
  assert(captured);
  assert(store.calls.some((call) => call.includes("/refund")));
  assertEquals(store.orphans.length, 0);
  assertEquals(
    store.calls.some((call) => call.includes("captureAuthorizedPayment")),
    false,
  );
});

Deno.test("release atrasado não apaga a reserva que o reclaim já assumiu", async () => {
  const store = makeStore();
  let releaseLoser: () => void = () => undefined;
  const loserGate = new Promise<void>((resolve) => {
    releaseLoser = resolve;
  });
  let loserInside: () => void = () => undefined;
  const loserInsideGate = new Promise<void>((resolve) => {
    loserInside = resolve;
  });
  let releaseWinner: () => void = () => undefined;
  const winnerGate = new Promise<void>((resolve) => {
    releaseWinner = resolve;
  });
  let winnerInside: () => void = () => undefined;
  const winnerInsideGate = new Promise<void>((resolve) => {
    winnerInside = resolve;
  });
  let pixPosts = 0;
  const asaas = providerFor(store, {
    onPixPost: async (payment) => {
      pixPosts += 1;
      if (pixPosts === 1) {
        const row = store.charges[0];
        if (row) row.reserved_at = expiredAt();
        loserInside();
        await loserGate;
        return new Response(
          JSON.stringify({ errors: [{ code: "invalid_value" }] }),
          { status: 400 },
        );
      }
      winnerInside();
      await winnerGate;
      return payment;
    },
  });
  const runtime = chargeRuntime(store, asaas);
  const loser = createCharge(request("PIX", "idem-release-a"), runtime);
  await loserInsideGate;
  const winner = createCharge(request("PIX", "idem-release-b"), runtime);
  await winnerInsideGate;
  releaseLoser();
  await loser;
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, null);
  releaseWinner();
  const won = await winner;
  const body = await won.json();
  assertEquals(won.status, 200);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, body.provider_ref);
  assertEquals(body.status, "pending");
});

Deno.test("captura com erro estorna e não deixa a cobrança em creating", async () => {
  const store = makeStore();
  store.closed = true;
  const asaas = providerFor(store, {
    onCapture: () => Promise.resolve(new Response("falhou", { status: 500 })),
  });
  const response = await createCharge(
    request("CREDIT_CARD", "idem-capture-fail"),
    chargeRuntime(store, asaas),
  );
  const authorizedAt = store.calls.indexOf("transition authorized");
  const captureAt = store.calls.findIndex((call) =>
    call.includes("captureAuthorizedPayment")
  );
  const refundAt = store.calls.findIndex((call) => call.includes("/refund"));
  assert(authorizedAt >= 0 && authorizedAt < captureAt);
  assert(captureAt < refundAt);
  assertEquals(response.status, 502);
  assertEquals(store.charges.length, 0);
  assertEquals(store.orphans.length, 0);
  assertEquals(store.member, "released");
  assert(store.calls.includes("transition cancelled"));
});

Deno.test("estorno da captura que falha registra o órfão e fica authorized", async () => {
  const store = makeStore();
  store.closed = true;
  const asaas = providerFor(store, {
    onCapture: () => Promise.resolve(new Response("falhou", { status: 500 })),
    onRefund: () => Promise.resolve(new Response("falhou", { status: 500 })),
  });
  const response = await createCharge(
    request("CREDIT_CARD", "idem-refund-fail"),
    chargeRuntime(store, asaas),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.status, "authorized");
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].status, "authorized");
  assertEquals(store.orphans.length, 1);
  assertEquals(store.orphans[0].reason, "refund_failed");
  assertEquals(store.member, "reserved");
});

function openPix(store: Store, id = "pay_pix") {
  store.charges[0].billing_type = "PIX";
  store.charges[0].status = "pending";
  store.charges[0].provider_ref = id;
  store.charges[0].qr_code = "qr-antigo";
  store.charges[0].reserved_at = freshAt();
  store.payments.push({
    id,
    status: "PENDING",
    billingType: "PIX",
    externalReference: `pix:${groupId}:${userId}`,
    customer: "cus_1",
    value: 100,
    split: [{ walletId: "wal_house", fixedValue: 90 }],
    deleteAsPending: true,
  });
}

Deno.test("troca Pix para cartão com deleted:true e PENDING", async () => {
  const store = makeStore({});
  openPix(store);
  const response = await createCharge(
    request("CREDIT_CARD", "idem-switch-1"),
    chargeRuntime(store, providerFor(store, {})),
  );
  const body = await response.json();
  const cardPost = store.calls.findIndex((call) =>
    call.startsWith("POST ") && call.endsWith("/payments")
  );
  const deleted = store.calls.findIndex((call) => call.startsWith("DELETE "));
  assert(cardPost >= 0 && cardPost < deleted);
  assertEquals(response.status, 200);
  assertEquals(body.billing_type, "CREDIT_CARD");
  assertEquals(body.status, "authorized");
  assertEquals(body.qr_code, null);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].billing_type, "CREDIT_CARD");
  assertEquals(store.charges[0].qr_code, null);
  assertEquals(store.charges[0].provider_ref, body.provider_ref);
  assertEquals(store.orphans.length, 0);
  assertEquals(store.payments[0].deleted, true);
  assertEquals(store.payments[0].status, "PENDING");
});

Deno.test("troca para cartão trata Pix 404 como já cancelado", async () => {
  const store = makeStore({});
  openPix(store, "pay_sumiu");
  store.payments.length = 0;
  const response = await createCharge(
    request("CREDIT_CARD", "idem-switch-404"),
    chargeRuntime(store, providerFor(store, {})),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.billing_type, "CREDIT_CARD");
  assertEquals(body.status, "authorized");
  assertEquals(store.orphans.length, 0);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].billing_type, "CREDIT_CARD");
  assertEquals(store.charges[0].provider_ref, body.provider_ref);
  assert(store.calls.some((call) => call.startsWith("DELETE ")));
});

Deno.test("Pix pendente 404 abre outra cobrança sem órfão", async () => {
  const store = makeStore({});
  openPix(store, "pay_sumiu");
  store.payments.length = 0;
  const response = await createCharge(
    request("PIX", "idem-pix-404"),
    chargeRuntime(store, providerFor(store, {})),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.billing_type, "PIX");
  assertEquals(body.status, "pending");
  assertEquals(store.orphans.length, 0);
  assert(body.provider_ref !== "pay_sumiu");
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, body.provider_ref);
});

Deno.test("cartão recusado não cancela o Pix nem reserva a vaga", async () => {
  const store = makeStore({});
  openPix(store);
  const response = await createCharge(
    request("CREDIT_CARD", "idem-declined-1"),
    chargeRuntime(
      store,
      providerFor(store, {
        onCardPost: () =>
          Promise.resolve(
            new Response(
              JSON.stringify({
                errors: [{
                  code: "invalid_creditCard",
                  description: "Transação não autorizada.",
                }],
              }),
              { status: 400 },
            ),
          ),
      }),
    ),
  );
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.error, "card_declined");
  assertEquals(store.calls.some((call) => call.startsWith("DELETE ")), false);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].billing_type, "PIX");
  assertEquals(store.charges[0].status, "pending");
  assertEquals(store.charges[0].provider_ref, "pay_pix");
  assertEquals(store.charges[0].qr_code, "qr-antigo");
  assertEquals(store.orphans.length, 0);
  assertEquals(store.payments[0].deleted, undefined);
});

Deno.test("cartão ausente não reserva vaga nem mexe no Pix", async () => {
  const store = makeStore({});
  openPix(store);
  const missing = new Request("https://example.test/create-charge", {
    method: "POST",
    body: JSON.stringify({
      group_id: groupId,
      billing_type: "CREDIT_CARD",
      idempotency_key: "idem-sem-cartao",
    }),
  });
  const absentId = await createCharge(
    missing,
    chargeRuntime(store, providerFor(store, {})),
  );
  assertEquals(absentId.status, 400);
  const unknown = new Request("https://example.test/create-charge", {
    method: "POST",
    body: JSON.stringify({
      group_id: groupId,
      billing_type: "CREDIT_CARD",
      idempotency_key: "idem-cartao-alheio",
      saved_card_id: "99999999-9999-4999-8999-999999999999",
    }),
  });
  const notOwned = await createCharge(
    unknown,
    chargeRuntime(store, providerFor(store, {})),
  );
  assertEquals(notOwned.status, 403);
  assertEquals(store.calls.some((call) => call.includes("/payments")), false);
  assertEquals(store.charges[0].billing_type, "PIX");
  assertEquals(store.charges[0].qr_code, "qr-antigo");
  assertEquals(store.charges.length, 1);
});

Deno.test("Pix apagado com PENDING não devolve o QR antigo", async () => {
  const store = makeStore({});
  openPix(store);
  store.payments[0].deleted = true;
  const response = await createCharge(
    request("PIX", "idem-pix-de-novo"),
    chargeRuntime(store, providerFor(store, {})),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.billing_type, "PIX");
  assertEquals(body.qr_code, "qr");
  assertEquals(body.qr_code === "qr-antigo", false);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].provider_ref, body.provider_ref);
  assertEquals(store.charges[0].provider_ref === "pay_pix", false);
});

Deno.test("Pix apagado sem detach_gone_pix ainda solta o QR", async () => {
  const store = makeStore({});
  openPix(store);
  store.payments[0].deleted = true;
  store.detachMissing = true;
  const response = await createCharge(
    request("PIX", "idem-pix-sem-funcao"),
    chargeRuntime(store, providerFor(store, {})),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.qr_code, "qr");
  assertEquals(body.qr_code === "qr-antigo", false);
  assertEquals(store.charges.length, 1);
  assertEquals(store.charges[0].billing_type, "PIX");
  assertEquals(store.charges[0].provider_ref === "pay_pix", false);
  assertEquals(store.charges[0].qr_code === "qr-antigo", false);
});

Deno.test("reserva vencida que não apaga ainda cancela a autorização", async () => {
  const store = makeStore({
    billing_type: "CREDIT_CARD",
    status: "creating",
    provider_ref: null,
    idempotency_key: "idem-card-velho",
  });
  store.charges[0].reserved_at = expiredAt();
  store.releaseExpiredError = true;
  const response = await createCharge(
    request("CREDIT_CARD", "idem-card-novo"),
    chargeRuntime(store, providerFor(store, {})),
  );
  assertEquals(response.status, 500);
  const authorized = store.payments.find((item) =>
    item.billingType === "CREDIT_CARD"
  );
  assert(authorized?.status === "DELETED" || authorized?.status === "REFUNDED");
  assertEquals(store.charges[0].provider_ref, null);
});
