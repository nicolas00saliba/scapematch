import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  cacOutcome,
  cacReference,
  cacTransferBody,
  cacTransfersEnabled,
  runPlatformCac,
  secureTransferBase,
  type CacClaim,
  type CacTransferClient,
} from "./platform_cac.ts";

const chargeId = "c2540000-0000-4000-8000-000000000001";

Deno.test("a flag nasce desligada e o host seguro é o da transferência", () => {
  assertEquals(cacTransfersEnabled({ get: () => undefined }), false);
  assertEquals(cacTransfersEnabled({ get: () => "" }), false);
  assertEquals(cacTransfersEnabled({ get: () => "on" }), true);
  assertEquals(
    secureTransferBase("https://sandbox.api.pagseguro.com"),
    "https://secure.sandbox.api.pagseguro.com",
  );
  assertEquals(
    secureTransferBase("https://api.pagseguro.com"),
    "https://secure.api.pagseguro.com",
  );
  assertEquals(
    cacReference(chargeId),
    "cacc2540000000040008000000000000001",
  );
});

Deno.test("o corpo é P2P para a conta da casa, em centavos", () => {
  const body = cacTransferBody({
    chargeId,
    amountCents: 1000,
    accountId: "ACCO_CASA_CAC",
    notificationUrl: "https://exemplo.escapematch.test/functions/v1/pagbank-webhook",
  });
  assertEquals(body.instrument, {
    type: "P2P",
    p2p: { account_id: "ACCO_CASA_CAC" },
  });
  assertEquals(body.amount, { value: 1000, currency: "BRL" });
  assertEquals(body.notification_urls, [
    "https://exemplo.escapematch.test/functions/v1/pagbank-webhook",
  ]);
  assertEquals(cacOutcome(200, { id: "TRAN_1", status: "CREATED" }), "paid");
  assertEquals(cacOutcome(402, { message: "insufficient balance" }), "saldo");
  assertEquals(cacOutcome(200, {}), "failed");
});

Deno.test("sem a flag o worker não chama o cliente", async () => {
  let calls = 0;
  const client = fakeClient(() => {
    calls += 1;
    return { status: 200, body: { id: "TRAN_1", status: "CREATED" } };
  });
  const result = await runPlatformCac(
    { rpc: () => Promise.reject(new Error("nao devia")) },
    { get: () => "" },
    client,
  );
  assertEquals(result, { sent: 0, failed: 0 });
  assertEquals(calls, 0);
});

Deno.test("saldo curto não envia e avisa", async () => {
  const posts: unknown[] = [];
  const alerts: string[] = [];
  const original = console.error;
  console.error = (message?: unknown) => {
    alerts.push(String(message));
  };
  try {
    const completed: Record<string, unknown>[] = [];
    const result = await runPlatformCac(
      adminOf([claim()], completed),
      { get: (name) => name === "PAGBANK_CAC_TRANSFERS" ? "on" : "" },
      fakeClient((body) => {
        posts.push(body);
        return { status: 200, body: { id: "TRAN_1", status: "CREATED" } };
      }, 100),
    );
    assertEquals(posts, []);
    assertEquals(result, { sent: 0, failed: 1 });
    assertEquals(completed[0]?.p_error, "saldo");
    assert(alerts.some((line) => line.includes('"code":"saldo"')));
  } finally {
    console.error = original;
  }
});

Deno.test("com saldo o POST usa a referência e marca pago uma vez", async () => {
  const posts: { body: unknown; key: string }[] = [];
  const completed: Record<string, unknown>[] = [];
  const result = await runPlatformCac(
    adminOf([claim()], completed),
    { get: (name) => name === "PAGBANK_CAC_TRANSFERS" ? "on" : "" },
    fakeClient((body, key) => {
      posts.push({ body, key });
      return { status: 200, body: { id: "TRAN_CAC", status: "CREATED" } };
    }, 5000),
  );
  assertEquals(result, { sent: 1, failed: 0 });
  assertEquals(posts.length, 1);
  assertEquals(posts[0].key, cacReference(chargeId));
  assertEquals(
    (posts[0].body as { instrument: { type: string } }).instrument.type,
    "P2P",
  );
  assertEquals(completed[0]?.p_status, "paid");
  assertEquals(completed[0]?.p_provider_ref, "TRAN_CAC");
});

Deno.test("a oitava falha avisa que esgotou", async () => {
  const alerts: string[] = [];
  const original = console.error;
  console.error = (message?: unknown) => {
    alerts.push(String(message));
  };
  try {
    await runPlatformCac(
      adminOf([{ ...claim(), attempts: 8, account_id: null }], []),
      { get: (name) => name === "PAGBANK_CAC_TRANSFERS" ? "on" : "" },
      fakeClient(() => ({ status: 500, body: {} })),
    );
    assert(alerts.some((line) => line.includes('"code":"esgotado"')));
  } finally {
    console.error = original;
  }
});

function claim(): CacClaim {
  return {
    id: "c2590000-0000-4000-8000-000000000001",
    payment_charge_id: chargeId,
    venue_id: "c2520000-0000-4000-8000-000000000001",
    amount_cents: 1000,
    attempts: 1,
    account_id: "ACCO_CASA_CAC",
  };
}

function adminOf(
  rows: CacClaim[],
  completed: Record<string, unknown>[],
): { rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: null }> } {
  return {
    rpc(fn, args) {
      if (fn === "claim_platform_cac") return Promise.resolve({ data: rows, error: null });
      completed.push(args);
      return Promise.resolve({ data: null, error: null });
    },
  };
}

function fakeClient(
  post: (
    body: Record<string, unknown>,
    key: string,
  ) => { status: number; body: unknown },
  balance: number | null = 5000,
): CacTransferClient {
  return {
    notificationUrl: "https://exemplo.escapematch.test/functions/v1/pagbank-webhook",
    balanceCents: () => Promise.resolve(balance),
    postTransfer: (body, key) => Promise.resolve(post(body, key)),
  };
}
