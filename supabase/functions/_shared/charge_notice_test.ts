import { assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider, pagbankProductionBaseUrl } from "./pagbank_provider.ts";
import { pollPendingPagBankCharges } from "./charge_notice.ts";

const chargeId = "44444444-4444-4444-8444-444444444444";
const groupId = "11111111-1111-4111-8111-111111111111";

function adminFor(rows: Record<string, unknown>[]) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const chain = (table: string) => {
    const self = {
      select() {
        return self;
      },
      eq() {
        return self;
      },
      not() {
        return self;
      },
      neq() {
        return self;
      },
      order() {
        return self;
      },
      limit() {
        return self;
      },
      update() {
        return self;
      },
      maybeSingle() {
        if (table === "groups") {
          return Promise.resolve({
            data: {
              cancelled_at: null,
              confirmed_at: "2026-11-06T10:00:00Z",
              closed_at: null,
              closes_at: "2099-01-01T00:00:00Z",
              total_spots: 4,
              minimum_spots: 2,
            },
            error: null,
          });
        }
        return Promise.resolve({
          data: { payer_document_status: "matched" },
          error: null,
        });
      },
      then(resolve: (value: unknown) => void) {
        resolve({
          data: table === "payment_charges" ? rows : null,
          error: null,
          count: 4,
        });
      },
    };
    return self;
  };
  return {
    calls,
    from(table: string) {
      return chain(table);
    },
    rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      if (fn === "apply_payment_transition") {
        return Promise.resolve({ data: { status: "paid" }, error: null });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
}

function provider(status: string) {
  return new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    () =>
      Promise.resolve(new Response(JSON.stringify({
        id: "CHAR_PENDENTE",
        status,
        payment_method: { type: "PIX" },
      }), { status: 200 })),
  );
}

const pending = {
  id: chargeId,
  group_id: groupId,
  user_id: "22222222-2222-4222-8222-222222222222",
  venue_id: "33333333-3333-4333-8333-333333333333",
  amount_cents: 500,
  commission_bps: 1000,
  status: "pending",
  billing_type: "PIX",
  provider_ref: "CHAR_PENDENTE",
  provider_split_id: "SPLI_PIX",
  custody_released_at: null,
  created_at: "2026-11-01T00:00:00Z",
};

Deno.test("Pix pendente pago no PagBank segue a lógica do webhook", async () => {
  const admin = adminFor([pending]);
  const applied = await pollPendingPagBankCharges(
    admin,
    provider("PAID"),
    { get: () => undefined },
  );
  assertEquals(applied, 1);
  const transition = admin.calls.find((call) =>
    call.fn === "apply_payment_transition"
  );
  assertEquals(transition?.args.p_charge_id, chargeId);
  assertEquals(transition?.args.p_next_status, "paid");
  assertEquals(transition?.args.p_credit, true);
});

Deno.test("Pix ainda aguardando não move a cobrança", async () => {
  const admin = adminFor([pending]);
  const applied = await pollPendingPagBankCharges(
    admin,
    provider("WAITING"),
    { get: () => undefined },
  );
  assertEquals(applied, 0);
  assertEquals(admin.calls, []);
});
