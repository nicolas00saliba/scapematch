import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";
import { handleReconcile } from "./index.ts";

type Call = { name: string; args: Record<string, unknown> };

function adminFor(work: unknown, calls: Call[]) {
  return {
    rpc(name: string, args: Record<string, unknown> = {}) {
      calls.push({ name, args });
      if (name === "list_payment_reconciliation") {
        return Promise.resolve({ data: work, error: null });
      }
      if (name === "release_expired_pix_reservation") {
        return Promise.resolve({ data: true, error: null });
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
    rpc.some((call) => call.name === "release_expired_pix_reservation"),
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

Deno.test("órfão capturado é estornado e marcado; falha de estorno fica pendente", async () => {
  const orphan = {
    id: "88888888-8888-8888-8888-888888888888",
    provider_ref: "pay_orfao",
    charge_id: "44444444-4444-4444-4444-444444444444",
    attempt_id: null,
    billing_type: "CREDIT_CARD",
    external_reference: "idem-card-1",
  };
  const okCalls: Call[] = [];
  const okHttp: string[] = [];
  const ok = await reconcilePayments(
    adminFor({ creating: [], orphans: [orphan] }, okCalls),
    providerFor(okHttp, [{
      id: "pay_orfao",
      status: "CONFIRMED",
      billingType: "CREDIT_CARD",
      externalReference: "idem-card-1",
    }]),
  );
  assertEquals(ok, { resolved: 1, pending: 0 });
  assert(okCalls.some((call) =>
    call.name === "apply_payment_transition" &&
    call.args.p_next_status === "refunded"
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
        external_reference: null,
      }],
    }, calls),
    providerFor(http, []),
  );
  assertEquals(result.resolved, 1);
  assert(http.some((call) => call.includes("/payments/pay_gone")));
  assertEquals(http.some((call) => call.includes("/refund")), false);
  assert(calls.some((call) => call.name === "mark_orphan_resolved"));
});

Deno.test("reconcile-payments recusa quem não é a service role", async () => {
  const missing = await handleReconcile(
    new Request("https://example.test/reconcile-payments", { method: "POST" }),
    { serviceKey: "service-role-test" },
  );
  assertEquals(missing.status, 401);
  const accepted = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { Authorization: "Bearer service-role-test" },
    }),
    {
      serviceKey: "service-role-test",
      admin: adminFor({ creating: [], orphans: [] }, []),
      asaas: providerFor([], []),
    },
  );
  assertEquals(accepted.status, 200);
  assertEquals(await accepted.json(), { resolved: 0, pending: 0 });
});
