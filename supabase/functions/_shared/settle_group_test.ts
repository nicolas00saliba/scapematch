import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "./asaas_provider.ts";
import { maySettle, settleGroup } from "./settle_group.ts";

const groupId = "11111111-1111-4111-8111-111111111111";
const userId = "22222222-2222-4222-8222-222222222222";
const venueId = "33333333-3333-4333-8333-333333333333";
const chargeId = "44444444-4444-4444-8444-444444444444";

type Charge = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
  status: string;
  provider_ref: string | null;
  billing_type: string;
};

function adminFor(options: {
  closed?: boolean;
  cancelled?: boolean;
  filled?: number;
  total?: number;
  minimum?: number;
  charges: Charge[];
  claim?: () => boolean;
  member?: string | null;
  creator?: string;
  owner?: string;
}) {
  const calls: string[] = [];
  return {
    calls,
    from(table: string) {
      let head = false;
      const self = {
        select(_cols: string, opts?: { head?: boolean }) {
          head = Boolean(opts?.head);
          return self;
        },
        eq() {
          return self;
        },
        neq() {
          return self;
        },
        limit() {
          return self;
        },
        maybeSingle() {
          return Promise.resolve(row());
        },
        then(resolve: (value: unknown) => void) {
          resolve(row());
        },
      };
      const row = () => {
        if (table === "groups") {
          return {
            data: {
              id: groupId,
              created_by: options.creator ?? userId,
              venue_id: venueId,
              cancelled_at: options.cancelled ? "2026-11-06T10:00:00Z" : null,
              closed_at: options.closed ? "2026-11-06T10:00:00Z" : null,
              closes_at: "2026-11-07T10:00:00Z",
              total_spots: options.total ?? 4,
              minimum_spots: options.minimum ?? 2,
            },
            error: null,
            count: 1,
          };
        }
        if (table === "group_members") {
          if (head) {
            return { data: null, error: null, count: options.filled ?? 4 };
          }
          return {
            data: options.member === null
              ? null
              : { attendance: options.member ?? "confirmed" },
            error: null,
            count: options.filled ?? 4,
          };
        }
        if (table === "payment_charges") {
          return {
            data: options.charges,
            error: null,
            count: options.charges.length,
          };
        }
        if (table === "venues") {
          return {
            data: { owner_id: options.owner ?? "owner-1" },
            error: null,
          };
        }
        if (table === "fiscal_invoices") {
          return {
            data: [{ kind: "service" }, { kind: "commission" }],
            error: null,
          };
        }
        return { data: null, error: null, count: 0 };
      };
      return self;
    },
    rpc(name: string, args: Record<string, unknown>) {
      calls.push(name);
      if (name === "claim_card_capture") {
        const ok = options.claim ? options.claim() : true;
        return Promise.resolve({ data: ok, error: null });
      }
      if (name === "release_card_capture_claim") {
        return Promise.resolve({ data: null, error: null });
      }
      if (name === "apply_payment_transition") {
        const charge = options.charges.find((item) =>
          item.id === args.p_charge_id
        );
        if (charge) charge.status = String(args.p_next_status);
        return Promise.resolve({
          data: {
            applied: true,
            status: args.p_next_status,
            paid_at: "2026-11-06T10:05:00Z",
            refunded_at: null,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: { code: "42883" } });
    },
  };
}

function provider(remoteStatus: string, captures: string[]) {
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    if (method === "GET" && url.includes("/payments/pay_card")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            id: "pay_card",
            status: remoteStatus,
            billingType: "CREDIT_CARD",
            deleted: false,
          }),
          { status: 200 },
        ),
      );
    }
    if (method === "POST" && url.includes("captureAuthorizedPayment")) {
      captures.push(url);
      return Promise.resolve(
        new Response(
          JSON.stringify({ id: "pay_card", status: "CONFIRMED" }),
          { status: 200 },
        ),
      );
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  return new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
    () => Promise.resolve(),
  );
}

function card(): Charge {
  return {
    id: chargeId,
    group_id: groupId,
    user_id: userId,
    venue_id: venueId,
    amount_cents: 10000,
    commission_bps: 1000,
    status: "authorized",
    provider_ref: "pay_card",
    billing_type: "CREDIT_CARD",
  };
}

Deno.test("grupo fechado captura o cartão autorizado uma vez", async () => {
  const charges = [card()];
  let claims = 0;
  const admin = adminFor({
    closed: true,
    charges,
    claim: () => {
      claims += 1;
      return claims === 1;
    },
  });
  const captures: string[] = [];
  const asaas = provider("AUTHORIZED", captures);
  await settleGroup(admin, asaas, groupId);
  await settleGroup(admin, asaas, groupId);
  assertEquals(captures.length, 1);
  assertEquals(charges[0].status, "paid");
  assert(admin.calls.includes("apply_payment_transition"));
});

Deno.test("cartão já confirmado no Asaas não captura de novo", async () => {
  const charges = [card()];
  const admin = adminFor({ closed: true, charges });
  const captures: string[] = [];
  await settleGroup(admin, provider("CONFIRMED", captures), groupId);
  assertEquals(captures.length, 0);
  assertEquals(charges[0].status, "paid");
});

Deno.test("grupo ainda aberto não captura", async () => {
  const charges = [card()];
  const admin = adminFor({
    closed: false,
    filled: 2,
    total: 4,
    charges,
  });
  const captures: string[] = [];
  await settleGroup(admin, provider("AUTHORIZED", captures), groupId);
  assertEquals(captures.length, 0);
  assertEquals(charges[0].status, "authorized");
});

Deno.test("trava de captura impede a segunda chamada simultânea", async () => {
  const charges = [card()];
  const admin = adminFor({
    closed: true,
    charges,
    claim: () => false,
  });
  const captures: string[] = [];
  await settleGroup(admin, provider("AUTHORIZED", captures), groupId);
  assertEquals(captures.length, 0);
  assertEquals(charges[0].status, "authorized");
});

Deno.test("migração não expõe a trava nem cria segredo novo", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261106120000_settle_on_close.sql",
      import.meta.url,
    ),
  );
  assert(
    sql.includes("raise sqlstate 'PT404' using message = 'unknown session'"),
  );
  assert(sql.includes("claim_card_capture"));
  assert(sql.includes("detach_gone_pix"));
  assert(sql.includes("x-reconcile-secret"));
  assert(sql.includes("revoke select (capture_claimed_at)"));
  assertEquals(sql.includes("service_role_key"), false);
  assertEquals(sql.includes("alter table vault"), false);
});

Deno.test("membro liquida grupo fechado e não o grupo aberto", async () => {
  const member = "33333333-3333-4333-8333-333333333334";
  const closed = adminFor({
    closed: true,
    charges: [],
    creator: userId,
    member: "confirmed",
  });
  assertEquals(await maySettle(closed, groupId, member, false), true);
  const open = adminFor({
    closed: false,
    filled: 1,
    total: 4,
    charges: [],
    creator: userId,
    member: "confirmed",
  });
  assertEquals(await maySettle(open, groupId, member, false), false);
  assertEquals(await maySettle(open, groupId, userId, false), true);
});
