import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import {
  reconcileAsaasTimeoutMs,
  reconcilePayments,
} from "../_shared/reconcile_payments.ts";
import { pixLeaseMs } from "../_shared/pix_charge.ts";
import { handleReconcile } from "./index.ts";

type Call = { name: string; args: Record<string, unknown> };
type SettleMode = "apply" | "skip" | "fail" | "attempt" | "lost";

function adminFor(
  work: unknown,
  calls: Call[],
  settle: SettleMode = "apply",
) {
  return {
    rpc(name: string, args: Record<string, unknown> = {}) {
      calls.push({ name, args });
      if (name === "claim_payment_reconciliation") {
        return Promise.resolve({ data: work, error: null });
      }
      if (
        name === "confirm_reconcile_claim" || name === "confirm_orphan_claim"
      ) {
        return Promise.resolve({ data: settle !== "lost", error: null });
      }
      if (name === "settle_orphan_charge") {
        if (settle === "fail") {
          return Promise.resolve({ data: null, error: { message: "erro" } });
        }
        if (settle === "attempt") {
          return Promise.resolve({
            data: { applied: false, skipped: false, status: "authorized" },
            error: null,
          });
        }
        if (settle === "skip") {
          return Promise.resolve({
            data: { applied: false, skipped: true },
            error: null,
          });
        }
        return Promise.resolve({
          data: {
            applied: true,
            skipped: false,
            status: args.p_next_status,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };
}

function providerFor(
  calls: string[],
  payments: Record<string, unknown>[],
  options?: { refundStatus?: number; deleteStatus?: number },
) {
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    calls.push(`${method} ${url}`);
    if (method === "GET" && url.includes("externalReference=")) {
      const reference = new URL(url).searchParams.get("externalReference");
      const rows = payments.filter((item) =>
        item.externalReference === reference
      );
      return Promise.resolve(
        new Response(JSON.stringify({ data: rows }), { status: 200 }),
      );
    }
    const match = url.match(/\/payments\/([^/?]+)(?:\/refund)?$/);
    if (match && method === "GET") {
      const payment = payments.find((item) => item.id === match[1]);
      if (!payment) {
        return Promise.resolve(new Response("não", { status: 404 }));
      }
      return Promise.resolve(
        new Response(JSON.stringify(payment), { status: 200 }),
      );
    }
    if (match && method === "DELETE") {
      const payment = payments.find((item) => item.id === match[1]);
      if (payment) payment.status = "DELETED";
      return Promise.resolve(
        new Response(JSON.stringify({ id: match[1], deleted: true }), {
          status: options?.deleteStatus ?? 200,
        }),
      );
    }
    if (url.endsWith("/refund") && method === "POST") {
      const id = match?.[1] ?? "pay";
      return Promise.resolve(
        new Response(JSON.stringify({ id, status: "REFUNDED" }), {
          status: options?.refundStatus ?? 200,
        }),
      );
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  return new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
}

const creatingCard = {
  charge_id: "44444444-4444-4444-4444-444444444444",
  attempt_id: "55555555-5555-5555-5555-555555555555",
  billing_type: "CREDIT_CARD",
  external_reference: "idem-card-1",
};

const attemptId = "55555555-5555-5555-5555-555555555555";

Deno.test("creating vencido sem cobrança no Asaas libera a reserva", async () => {
  const rpc: Call[] = [];
  const http: string[] = [];
  const result = await reconcilePayments(
    adminFor({ creating: [creatingCard], orphans: [] }, rpc),
    providerFor(http, []),
  );
  assertEquals(result, { resolved: 1, pending: 0 });
  assert(http.some((call) => call.includes("externalReference=idem-card-1")));
  assertEquals(
    rpc.some((call) =>
      call.name === "release_pix_reservation" &&
      call.args.p_attempt_id === attemptId
    ),
    true,
  );
});

Deno.test("pré-autorização vencida sai com refund, Pix pendente com DELETE", async () => {
  const rpc: Call[] = [];
  const http: string[] = [];
  const work = {
    creating: [
      creatingCard,
      {
        charge_id: "66666666-6666-6666-6666-666666666666",
        attempt_id: "77777777-7777-7777-7777-777777777777",
        billing_type: "PIX",
        external_reference: "pix:g:u",
      },
    ],
    orphans: [],
  };
  const result = await reconcilePayments(
    adminFor(work, rpc),
    providerFor(http, [
      {
        id: "pay_card",
        status: "AUTHORIZED",
        billingType: "CREDIT_CARD",
        externalReference: "idem-card-1",
      },
      {
        id: "pay_pix",
        status: "PENDING",
        billingType: "PIX",
        externalReference: "pix:g:u",
      },
    ]),
  );
  assertEquals(result.resolved, 2);
  assert(rpc.some((call) =>
    call.name === "confirm_reconcile_claim" &&
    call.args.p_attempt_id === attemptId &&
    call.args.p_charge_id === creatingCard.charge_id
  ));
  assert(
    http.some((call) =>
      call === "POST https://api-sandbox.asaas.com/v3/payments/pay_card/refund"
    ),
  );
  assert(
    http.some((call) =>
      call.startsWith("DELETE ") && call.endsWith("/payments/pay_pix")
    ),
  );
  assertEquals(
    http.some((call) => call.includes("DELETE") && call.includes("pay_card")),
    false,
  );
});

Deno.test("órfão usa só o provider_ref e ignora outro pagamento vivo", async () => {
  const orphan = {
    id: "88888888-8888-8888-8888-888888888888",
    provider_ref: "pay_orfao",
    charge_id: "44444444-4444-4444-4444-444444444444",
    attempt_id: attemptId,
    billing_type: "CREDIT_CARD",
    claimed_at: "2026-11-05T12:00:00.000Z",
  };
  const okCalls: Call[] = [];
  const okHttp: string[] = [];
  const ok = await reconcilePayments(
    adminFor({ creating: [], orphans: [orphan] }, okCalls),
    providerFor(okHttp, [
      {
        id: "pay_orfao",
        status: "CONFIRMED",
        billingType: "CREDIT_CARD",
        externalReference: "idem-card-1",
      },
      {
        id: "pay_vivo",
        status: "CONFIRMED",
        billingType: "CREDIT_CARD",
        externalReference: "idem-card-1",
      },
    ]),
  );
  assertEquals(ok, { resolved: 1, pending: 0 });
  assertEquals(
    okHttp.some((call) => call.includes("externalReference=")),
    false,
  );
  assertEquals(
    okHttp.some((call) => call.includes("/payments/pay_vivo")),
    false,
  );
  assert(
    okHttp.some((call) =>
      call === "POST https://api-sandbox.asaas.com/v3/payments/pay_orfao/refund"
    ),
  );
  const transition = okCalls.find((call) =>
    call.name === "settle_orphan_charge"
  );
  assertEquals(transition?.args.p_provider_ref, "pay_orfao");
  assertEquals(transition?.args.p_attempt_id, attemptId);
  assertEquals(transition?.args.p_next_status, "refunded");
  assert(okCalls.some((call) =>
    call.name === "confirm_orphan_claim" &&
    call.args.p_claimed_at === "2026-11-05T12:00:00.000Z"
  ));
  assert(okCalls.some((call) => call.name === "mark_orphan_resolved"));

  const failCalls: Call[] = [];
  const fail = await reconcilePayments(
    adminFor({ creating: [], orphans: [orphan] }, failCalls),
    providerFor([], [{
      id: "pay_orfao",
      status: "CONFIRMED",
      billingType: "CREDIT_CARD",
      externalReference: "idem-card-1",
    }], { refundStatus: 500 }),
  );
  assertEquals(fail, { resolved: 0, pending: 1 });
  assertEquals(
    failCalls.some((call) => call.name === "mark_orphan_resolved"),
    false,
  );
});

Deno.test("lease vencido depois da retomada não cancela no Asaas", async () => {
  const rpc: Call[] = [];
  const http: string[] = [];
  const result = await reconcilePayments(
    adminFor(
      {
        creating: [creatingCard],
        orphans: [{
          id: "88888888-8888-8888-8888-888888888888",
          provider_ref: "pay_orfao",
          charge_id: creatingCard.charge_id,
          attempt_id: attemptId,
          billing_type: "CREDIT_CARD",
          claimed_at: "2026-11-05T12:00:00.000Z",
        }],
      },
      rpc,
      "lost",
    ),
    providerFor(http, [
      {
        id: "pay_card",
        status: "AUTHORIZED",
        billingType: "CREDIT_CARD",
        externalReference: "idem-card-1",
      },
      {
        id: "pay_orfao",
        status: "CONFIRMED",
        billingType: "CREDIT_CARD",
      },
    ]),
  );
  assertEquals(result, { resolved: 1, pending: 1 });
  assertEquals(http.some((call) => call.includes("/refund")), false);
  assertEquals(http.some((call) => call.includes("DELETE")), false);
  assert(rpc.some((call) => call.name === "confirm_reconcile_claim"));
  assert(rpc.some((call) => call.name === "confirm_orphan_claim"));
  assertEquals(
    rpc.some((call) => call.name === "record_orphan_payment"),
    false,
  );
  assertEquals(rpc.some((call) => call.name === "mark_orphan_resolved"), false);
});

Deno.test("erro ou attempt divergente não marca o órfão como resolvido", async () => {
  const orphan = {
    id: "88888888-8888-8888-8888-888888888888",
    provider_ref: "pay_orfao",
    charge_id: "44444444-4444-4444-4444-444444444444",
    attempt_id: attemptId,
    billing_type: "CREDIT_CARD",
  };
  const payment = [{
    id: "pay_orfao",
    status: "REFUNDED",
    billingType: "CREDIT_CARD",
  }];
  const errorCalls: Call[] = [];
  const errorResult = await reconcilePayments(
    adminFor({ creating: [], orphans: [orphan] }, errorCalls, "fail"),
    providerFor([], payment),
  );
  assertEquals(errorResult, { resolved: 0, pending: 1 });
  assertEquals(
    errorCalls.some((call) => call.name === "mark_orphan_resolved"),
    false,
  );

  const attemptCalls: Call[] = [];
  const attemptResult = await reconcilePayments(
    adminFor({ creating: [], orphans: [orphan] }, attemptCalls, "attempt"),
    providerFor([], payment),
  );
  assertEquals(attemptResult, { resolved: 0, pending: 1 });
  assertEquals(
    attemptCalls.some((call) => call.name === "mark_orphan_resolved"),
    false,
  );
});

Deno.test("órfão já estornado no Asaas só marca resolvido", async () => {
  const calls: Call[] = [];
  const http: string[] = [];
  const result = await reconcilePayments(
    adminFor({
      creating: [],
      orphans: [{
        id: "99999999-9999-9999-9999-999999999999",
        provider_ref: "pay_gone",
        charge_id: null,
        attempt_id: null,
        billing_type: "CREDIT_CARD",
      }],
    }, calls),
    providerFor(http, []),
  );
  assertEquals(result.resolved, 1);
  assert(http.some((call) => call.includes("/payments/pay_gone")));
  assertEquals(http.some((call) => call.includes("externalReference=")), false);
  assertEquals(http.some((call) => call.includes("/refund")), false);
  assert(calls.some((call) => call.name === "mark_orphan_resolved"));
});

Deno.test("órfão já liquidado solta a cobrança presa antes de resolver", async () => {
  const chargeId = "44444444-4444-4444-4444-444444444444";
  const refundedCalls: Call[] = [];
  const refunded = await reconcilePayments(
    adminFor(
      {
        creating: [],
        orphans: [{
          id: "99999999-9999-9999-9999-999999999999",
          provider_ref: "pay_refunded",
          charge_id: chargeId,
          attempt_id: attemptId,
          billing_type: "CREDIT_CARD",
        }],
      },
      refundedCalls,
    ),
    providerFor([], [{
      id: "pay_refunded",
      status: "REFUNDED",
      billingType: "CREDIT_CARD",
      externalReference: "idem-card-1",
    }, {
      id: "pay_vivo",
      status: "CONFIRMED",
      billingType: "CREDIT_CARD",
      externalReference: "idem-card-1",
    }]),
  );
  assertEquals(refunded, { resolved: 1, pending: 0 });
  const refundedTransition = refundedCalls.findIndex((call) =>
    call.name === "settle_orphan_charge" &&
    call.args.p_next_status === "refunded" &&
    call.args.p_attempt_id === attemptId &&
    call.args.p_provider_ref === "pay_refunded"
  );
  const refundedMark = refundedCalls.findIndex((call) =>
    call.name === "mark_orphan_resolved"
  );
  assert(refundedTransition >= 0 && refundedTransition < refundedMark);

  const missingCalls: Call[] = [];
  const missingHttp: string[] = [];
  const missing = await reconcilePayments(
    adminFor(
      {
        creating: [],
        orphans: [{
          id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          provider_ref: "pay_deleted",
          charge_id: chargeId,
          attempt_id: attemptId,
          billing_type: "CREDIT_CARD",
        }],
      },
      missingCalls,
    ),
    providerFor(missingHttp, []),
  );
  assertEquals(missing, { resolved: 1, pending: 0 });
  assertEquals(
    missingHttp.some((call) => call.includes("externalReference=")),
    false,
  );
  const missingTransition = missingCalls.findIndex((call) =>
    call.name === "settle_orphan_charge" &&
    call.args.p_next_status === "cancelled" &&
    call.args.p_provider_ref === "pay_deleted"
  );
  const missingMark = missingCalls.findIndex((call) =>
    call.name === "mark_orphan_resolved"
  );
  assert(missingTransition >= 0 && missingTransition < missingMark);

  const otherCalls: Call[] = [];
  const other = await reconcilePayments(
    adminFor(
      {
        creating: [],
        orphans: [{
          id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          provider_ref: "pay_refunded",
          charge_id: chargeId,
          attempt_id: attemptId,
          billing_type: "CREDIT_CARD",
        }],
      },
      otherCalls,
      "skip",
    ),
    providerFor([], [{
      id: "pay_refunded",
      status: "REFUNDED",
      billingType: "CREDIT_CARD",
    }]),
  );
  assertEquals(other, { resolved: 1, pending: 0 });
  assertEquals(
    otherCalls.some((call) => call.name === "settle_orphan_charge"),
    true,
  );
  assert(otherCalls.some((call) => call.name === "mark_orphan_resolved"));
});

Deno.test("reconcile-payments só aceita o segredo do cron", async () => {
  const secret = "segredo-reconcile-teste";
  const missing = await handleReconcile(
    new Request("https://example.test/reconcile-payments", { method: "POST" }),
    { reconcileSecret: secret },
  );
  assertEquals(missing.status, 401);
  const bearer = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { Authorization: "Bearer service-role-test" },
    }),
    { reconcileSecret: secret },
  );
  assertEquals(bearer.status, 401);
  const wrong = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": "outro" },
    }),
    { reconcileSecret: secret },
  );
  assertEquals(wrong.status, 401);
  const empty = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": secret },
    }),
    { reconcileSecret: "" },
  );
  assertEquals(empty.status, 401);
  const accepted = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": secret },
    }),
    {
      reconcileSecret: secret,
      admin: adminFor({ creating: [], orphans: [] }, []),
      asaas: providerFor([], []),
    },
  );
  assertEquals(accepted.status, 200);
  assertEquals(await accepted.json(), { resolved: 0, pending: 0 });
});

Deno.test("migrações cercam a chave, o lote e o cron sem service role", async () => {
  const wallet = await Deno.readTextFile(
    new URL(
      "../../migrations/20261105220000_subaccount_key_wallet.sql",
      import.meta.url,
    ),
  );
  const claim = await Deno.readTextFile(
    new URL(
      "../../migrations/20261105221000_payment_reconcile.sql",
      import.meta.url,
    ),
  );
  const schedule = await Deno.readTextFile(
    new URL(
      "../../migrations/20261105222000_payment_reconcile_schedule.sql",
      import.meta.url,
    ),
  );
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assert(wallet.includes("asaas_subaccount_key ausente no vault"));
  assertEquals(wallet.includes("vault.create_secret"), false);
  assert(claim.includes("for update skip locked"));
  assert(claim.includes("limit 10"));
  assertEquals(claim.includes("limit 50"), false);
  assert(claim.includes("confirm_reconcile_claim"));
  assert(claim.includes("confirm_orphan_claim"));
  assert(reconcileAsaasTimeoutMs * 4 < pixLeaseMs);
  assert(claim.includes("order by"));
  assertEquals(claim.includes("left join"), false);
  assert(schedule.includes("x-reconcile-secret"));
  assert(schedule.includes("reconcile_secret"));
  assertEquals(schedule.includes("reconcile_payments_authorization"), false);
  assertEquals(schedule.includes("Authorization"), false);
  const section = config.split("[functions.reconcile-payments]")[1] ?? "";
  assert(section.split("\n")[1]?.includes("verify_jwt = false"));
});
