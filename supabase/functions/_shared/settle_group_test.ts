import { assert, assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider } from "./pagbank_provider.ts";
import { memberPaymentForStatus } from "./charge_patch.ts";
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
  charged_amount_cents?: number;
  buyer_interest_cents?: number;
  commission_bps: number;
  status: string;
  provider_ref: string | null;
  billing_type: string;
  provider_split_id?: string | null;
};

function adminFor(options: {
  closed?: boolean;
  confirmed?: boolean;
  cancelled?: boolean;
  filled?: number;
  total?: number;
  minimum?: number;
  closesAt?: string;
  charges: Charge[];
  claim?: () => boolean;
  member?: string | null;
  creator?: string;
  owner?: string;
}) {
  const calls: string[] = [];
  const transitions: Record<string, unknown>[] = [];
  return {
    calls,
    transitions,
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
        update(values: Record<string, unknown>) {
          calls.push(`update:${table}`);
          transitions.push(values);
          return self;
        },
        is() {
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
              confirmed_at: options.confirmed ? "2026-11-06T10:00:00Z" : null,
              closed_at: options.closed ? "2026-11-06T10:00:00Z" : null,
              closes_at: options.closesAt ?? "2026-11-07T10:00:00Z",
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
            data: {
              owner_id: options.owner ?? "owner-1",
              pagbank_account_id: "ACCO_VENUE",
            },
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
        transitions.push(args);
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

function provider(
  remoteStatus: string,
  captures: string[],
  deleted = false,
) {
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    if (method === "GET" && url.includes("CHAR_CARD")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            id: "CHAR_CARD",
            status: remoteStatus,
            billingType: "CREDIT_CARD",
            deleted,
          }),
          { status: 200 },
        ),
      );
    }
    if (method === "POST" && url.includes("/custody/release")) {
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    if (method === "POST" && url.includes("/capture")) {
      captures.push(url);
      return Promise.resolve(
        new Response(
          JSON.stringify({ id: "CHAR_CARD", status: "CONFIRMED" }),
          { status: 200 },
        ),
      );
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  return new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    fetchFn,
    () => Promise.resolve(),
    "ACCO_PRIMARY",
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
    provider_ref: "CHAR_CARD",
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
  const pagbank = provider("AUTHORIZED", captures);
  await settleGroup(admin, pagbank, groupId);
  await settleGroup(admin, pagbank, groupId);
  assertEquals(captures.length, 1);
  assertEquals(charges[0].status, "paid");
  assert(admin.calls.includes("apply_payment_transition"));
});

Deno.test("cartão já confirmado no PagBank não captura de novo", async () => {
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
    minimum: 4,
    closesAt: "2099-11-07T10:00:00Z",
    charges,
  });
  const captures: string[] = [];
  await settleGroup(admin, provider("AUTHORIZED", captures), groupId);
  assertEquals(captures.length, 0);
  assertEquals(charges[0].status, "authorized");
});

Deno.test("provedor já encerrado não deixa o cartão authorized", async () => {
  const cases = [
    { status: "REFUNDED", deleted: false, local: "refunded" },
    { status: "PENDING", deleted: true, local: "cancelled" },
    { status: "CANCELED", deleted: false, local: "cancelled" },
    { status: "CANCELLED", deleted: false, local: "cancelled" },
    { status: "CONFIRMED", deleted: true, local: "cancelled" },
  ];
  for (const item of cases) {
    const charges = [card()];
    const admin = adminFor({ closed: true, charges });
    const captures: string[] = [];
    await settleGroup(
      admin,
      provider(item.status, captures, item.deleted),
      groupId,
    );
    assertEquals(captures.length, 0, item.status);
    assertEquals(charges[0].status, item.local, item.status);
    assertEquals(
      memberPaymentForStatus(charges[0].status).payment_status,
      "released",
      item.status,
    );
    assertEquals(
      admin.transitions.some((call) =>
        call.p_next_status === "paid" || call.p_credit === true
      ),
      false,
      item.status,
    );
  }
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

Deno.test("prazo vencido sem confirmação cancela e não captura", async () => {
  const charges = [card()];
  const admin = adminFor({
    closed: false,
    confirmed: false,
    filled: 4,
    total: 6,
    minimum: 4,
    closesAt: "2020-01-01T00:00:00Z",
    charges,
  });
  const captures: string[] = [];
  await settleGroup(admin, provider("AUTHORIZED", captures), groupId);
  assertEquals(captures.length, 0);
  assertEquals(charges[0].status, "authorized");
  assert(
    admin.calls.includes("update:groups"),
    admin.calls.join(","),
  );
  assert(
    admin.transitions.some((call) =>
      call.cancel_reason === "O grupo não confirmou a tempo"
    ),
  );
});

Deno.test("Pix já pago no grupo confirmado solta a custódia", async () => {
  const charges = [{
    ...card(),
    status: "paid",
    billing_type: "PIX",
    provider_ref: "CHAR_PIX",
    provider_split_id: "SPLI_PIX",
  }];
  const admin = adminFor({ closed: true, charges });
  const releases: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    if ((init?.method ?? "GET") === "POST" && url.includes("/custody/release")) {
      const posted = JSON.parse(String(init?.body ?? "{}"));
      assertEquals(
        posted.receivers.map((item: { account: { id: string } }) => item.account.id),
        ["ACCO_VENUE", "ACCO_PRIMARY"],
      );
      releases.push(url);
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    fetchFn,
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  await settleGroup(admin, pagbank, groupId);
  assertEquals(releases.length, 1);
  assert(releases[0].includes("/splits/SPLI_PIX/custody/release"));
});

Deno.test("grupo confirmado captura mesmo sem lotar", async () => {
  const charges = [card()];
  const admin = adminFor({
    confirmed: true,
    closed: false,
    filled: 2,
    total: 4,
    minimum: 2,
    charges,
  });
  const captures: string[] = [];
  await settleGroup(admin, provider("AUTHORIZED", captures), groupId);
  assertEquals(captures.length, 1);
  assertEquals(charges[0].status, "paid");
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

Deno.test("captura de 4x usa o total com juros, não o principal", async () => {
  const charges = [{
    ...card(),
    charged_amount_cents: 20640,
    buyer_interest_cents: 640,
  }];
  const admin = adminFor({ closed: true, charges });
  const bodies: number[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    if (method === "GET") {
      return Promise.resolve(new Response(JSON.stringify({
        id: "CHAR_CARD",
        status: "AUTHORIZED",
        billingType: "CREDIT_CARD",
      }), { status: 200 }));
    }
    if (url.includes("/capture") || url.includes("/cancel")) {
      bodies.push(JSON.parse(String(init?.body)).amount.value);
      return Promise.resolve(new Response(JSON.stringify({
        id: "CHAR_CARD",
        status: url.includes("/capture") ? "PAID" : "CANCELED",
      }), { status: 200 }));
    }
    if (url.includes("/custody/release")) {
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    fetchFn,
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  await settleGroup(admin, pagbank, groupId);
  assertEquals(bodies, [20640]);
  assertEquals(charges[0].status, "paid");
  assertEquals(charges[0].amount_cents, 10000);
});
