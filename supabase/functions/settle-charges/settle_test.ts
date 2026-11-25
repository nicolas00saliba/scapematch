import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleSettle } from "./index.ts";

const groupId = "11111111-1111-4111-8111-111111111111";
const organizer = "22222222-2222-4222-8222-222222222222";
const player = "33333333-3333-4333-8333-333333333333";
const outsider = "44444444-4444-4444-8444-444444444444";

function jwt(aal: string): string {
  const body = btoa(JSON.stringify({ sub: "a", aal })).replace(/\+/g, "-")
    .replace(/\//g, "_").replace(/=+$/, "");
  return `Bearer h.${body}.s`;
}

function request(body: unknown, token = ""): Request {
  return new Request("https://example.test/settle-charges", {
    method: "POST",
    headers: token ? { Authorization: token } : {},
    body: JSON.stringify(body),
  });
}

type Claim = { p_group_id: string | null; p_user_id: string | null };

function scopeAdmin(input: {
  admin?: boolean;
  createdBy?: string;
  ownerId?: string;
  memberId?: string | null;
}) {
  const claims: Claim[] = [];
  const group = {
    id: groupId,
    created_by: input.createdBy ?? organizer,
    venue_id: "venue-1",
    cancelled_at: null,
    confirmed_at: "2026-11-24T12:00:00Z",
    closed_at: null,
    closes_at: null,
    starts_at: "2026-11-25T12:00:00Z",
    total_spots: 4,
    minimum_spots: 2,
  };
  return {
    claims,
    from(table: string) {
      const q = {
        select() {
          return q;
        },
        eq() {
          return q;
        },
        neq() {
          return q;
        },
        is() {
          return q;
        },
        not() {
          return q;
        },
        or() {
          return q;
        },
        order() {
          return q;
        },
        limit() {
          return q;
        },
        range() {
          return q;
        },
        update() {
          return q;
        },
        maybeSingle() {
          if (table === "admins") {
            return Promise.resolve({
              data: input.admin ? { user_id: "admin" } : null,
              error: null,
            });
          }
          if (table === "groups") {
            return Promise.resolve({ data: group, error: null });
          }
          if (table === "venues") {
            return Promise.resolve({
              data: { owner_id: input.ownerId ?? "owner" },
              error: null,
            });
          }
          if (table === "group_members") {
            return Promise.resolve({
              data: input.memberId ? { user_id: input.memberId, attendance: "confirmed" } : null,
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
        then(
          resolve: (value: { data: unknown[]; error: null; count: number }) => unknown,
          reject?: (reason: unknown) => unknown,
        ) {
          const rows = table === "groups" && input.admin ? [{ id: groupId }] : [];
          return Promise.resolve({ data: rows, error: null, count: 2 }).then(
            resolve,
            reject,
          );
        },
      };
      return q;
    },
    rpc(name: string, args: Record<string, unknown> = {}) {
      if (name === "claim_member_refunds") {
        claims.push({
          p_group_id: (args.p_group_id as string | null) ?? null,
          p_user_id: (args.p_user_id as string | null) ?? null,
        });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
}

const quietBank = {
  sandbox: true,
  getPayment: () => Promise.resolve({ status: "PAID" }),
  refund: () => Promise.resolve({ status: "REFUNDED" }),
  cancelAuthorization: () => Promise.resolve({ status: "CANCELED" }),
  cancelPaymentConfirmed: () => Promise.resolve(true),
  releaseCustody: () => Promise.resolve(),
};

Deno.test("settle sem sessão responde 401", async () => {
  const response = await handleSettle(request({ group_id: groupId }), {
    user: null,
  });
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "not authenticated" });
});

Deno.test("pessoa de fora do grupo responde 403 e não pega a fila", async () => {
  const admin = scopeAdmin({ memberId: null });
  const response = await handleSettle(
    request({ group_id: groupId, member_refund: true }, jwt("aal1")),
    { user: { id: outsider }, admin, pagbank: quietBank as never },
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "not member" });
  assertEquals(admin.claims, []);
});

Deno.test("admin só com aal1 não varre a fila inteira", async () => {
  const admin = scopeAdmin({ admin: true });
  const response = await handleSettle(
    request({ sweep: true }, jwt("aal1")),
    { user: { id: "admin" }, admin, pagbank: quietBank as never },
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "not admin" });
  assertEquals(admin.claims, []);
});

Deno.test("organizador no acerto só pega a fila do próprio grupo", async () => {
  const admin = scopeAdmin({ createdBy: organizer });
  const response = await handleSettle(
    request({ group_id: groupId }, jwt("aal1")),
    { user: { id: organizer }, admin, pagbank: quietBank as never },
  );
  assertEquals(response.status, 200);
  assertEquals(admin.claims, [{ p_group_id: groupId, p_user_id: null }]);
});

Deno.test("jogador no acerto só pega a própria cobrança", async () => {
  const admin = scopeAdmin({ memberId: player });
  const response = await handleSettle(
    request({ group_id: groupId }, jwt("aal1")),
    { user: { id: player }, admin, pagbank: quietBank as never },
  );
  assertEquals(response.status, 200);
  assertEquals(admin.claims, [{ p_group_id: groupId, p_user_id: player }]);
});

Deno.test("admin com aal2 na varredura pega o lote inteiro", async () => {
  const admin = scopeAdmin({ admin: true, createdBy: organizer });
  const response = await handleSettle(
    request({ sweep: true }, jwt("aal2")),
    { user: { id: "admin" }, admin, pagbank: quietBank as never },
  );
  assertEquals(response.status, 200);
  assertEquals(admin.claims, [{ p_group_id: null, p_user_id: null }]);
});

type QueueRow = {
  id: string;
  charge_id: string;
  group_id: string;
  user_id: string;
  action: string;
  status: string;
  attempts: number;
  lease_until: string | null;
};

function raceAdmin(queue: QueueRow[], refunds: string[]) {
  const charge = {
    id: "charge-1",
    amount_cents: 10000,
    charged_amount_cents: null,
    status: "paid",
    provider_ref: "CHAR_RACE",
    billing_type: "PIX",
    custody_released_at: null,
    refund_requested_at: "now",
  };
  return {
    from(table: string) {
      const filters: { column: string; value: unknown }[] = [];
      let patch: Record<string, unknown> | null = null;
      const q = {
        select() {
          return q;
        },
        eq(column: string, value: unknown) {
          filters.push({ column, value });
          return q;
        },
        update(next: Record<string, unknown>) {
          patch = next;
          return q;
        },
        maybeSingle() {
          if (table === "admins") {
            return Promise.resolve({ data: null, error: null });
          }
          if (table === "groups") {
            return Promise.resolve({
              data: { created_by: organizer, venue_id: "venue-1" },
              error: null,
            });
          }
          if (table === "venues") {
            return Promise.resolve({ data: { owner_id: "owner" }, error: null });
          }
          if (table === "group_members") {
            return Promise.resolve({
              data: { user_id: player },
              error: null,
            });
          }
          if (table === "payment_charges") {
            return Promise.resolve({ data: charge, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        then(
          resolve: (value: { data: unknown; error: null }) => unknown,
          reject?: (reason: unknown) => unknown,
        ) {
          if (patch && table === "member_refund_queue") {
            const rows = queue.filter((row) =>
              filters.every((filter) =>
                (row as Record<string, unknown>)[filter.column] === filter.value
              )
            );
            for (const row of rows) Object.assign(row, patch);
            return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
          }
          if (table === "payment_charges") {
            return Promise.resolve({ data: charge, error: null }).then(resolve, reject);
          }
          return Promise.resolve({ data: [], error: null }).then(resolve, reject);
        },
      };
      return q;
    },
    rpc(name: string, args: Record<string, unknown> = {}) {
      if (name === "apply_payment_transition") {
        charge.status = String(args.p_next_status);
        return Promise.resolve({
          data: { applied: true, status: charge.status },
          error: null,
        });
      }
      if (name !== "claim_member_refunds") {
        return Promise.resolve({ data: [], error: null });
      }
      const now = Date.now();
      for (const row of queue) {
        const until = Date.parse(row.lease_until ?? "");
        if (row.status === "processing" && until <= now) {
          row.status = "queued";
          row.lease_until = null;
        }
      }
      const picked = queue.filter((row) => {
        if (row.status !== "queued") return false;
        if (args.p_user_id && row.user_id !== args.p_user_id) return false;
        if (args.p_group_id && row.group_id !== args.p_group_id) return false;
        return true;
      }).slice(0, 20);
      const until = new Date(now + 90_000).toISOString();
      for (const row of picked) {
        row.status = "processing";
        row.lease_until = until;
        row.attempts += 1;
      }
      return Promise.resolve({ data: picked, error: null });
    },
    refunds,
  };
}

Deno.test("dois acertos ao mesmo tempo estornam a cobrança uma vez", async () => {
  const queue: QueueRow[] = [{
    id: "q-1",
    charge_id: "charge-1",
    group_id: groupId,
    user_id: player,
    action: "refund",
    status: "queued",
    attempts: 0,
    lease_until: null,
  }];
  const refunds: string[] = [];
  let release: () => void = () => undefined;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let started: () => void = () => undefined;
  const startedGate = new Promise<void>((resolve) => {
    started = resolve;
  });
  const admin = raceAdmin(queue, refunds);
  const pagbank = {
    sandbox: true,
    getPayment: () => Promise.resolve({ status: "PAID" }),
    refund: (id: string) => {
      refunds.push(id);
      if (refunds.length === 1) {
        started();
        return gate.then(() => ({ id, status: "REFUNDED" }));
      }
      return Promise.resolve({ id, status: "REFUNDED" });
    },
    cancelAuthorization: () => Promise.resolve({ status: "CANCELED" }),
    cancelPaymentConfirmed: () => Promise.resolve(true),
    releaseCustody: () => Promise.resolve(),
  };
  const body = { group_id: groupId, member_refund: true };
  const deps = { user: { id: player }, admin, pagbank: pagbank as never };
  const first = handleSettle(request(body, jwt("aal1")), deps);
  await startedGate;
  const second = await handleSettle(request(body, jwt("aal1")), deps);
  assertEquals(second.status, 200);
  assertEquals(await second.json(), { refunds: { done: 0, pending: 0 } });
  release();
  const winner = await first;
  assertEquals(winner.status, 200);
  assertEquals(await winner.json(), { refunds: { done: 1, pending: 0 } });
  assertEquals(refunds, ["CHAR_RACE"]);
  assertEquals(queue[0].status, "done");
  assert(queue[0].attempts === 1);
});
