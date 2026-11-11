import { assertEquals, assertRejects } from "jsr:@std/assert";
import { asaasProductionBaseUrl, asaasSandboxBaseUrl } from "./asaas_provider.ts";
import {
  backedCentsOf,
  pointsReserveMoves,
  pointsReserveSplitLine,
  postSandboxTransfer,
  readEnv,
  settlePointsReservePayout,
} from "./points_reserve_asaas.ts";

Deno.test("sem sandbox ou sem carteira o split da reserva não entra", () => {
  const base = {
    reserveWalletId: "wal_reserva",
    rootWalletId: "wal_raiz",
    houseWalletId: "wal_casa",
    referralCents: 250,
  };
  assertEquals(pointsReserveSplitLine({ ...base, sandbox: false }), null);
  assertEquals(
    pointsReserveSplitLine({ ...base, sandbox: true, referralCents: 0 }),
    null,
  );
  assertEquals(
    pointsReserveSplitLine({
      ...base,
      sandbox: true,
      reserveWalletId: "wal_raiz",
    }),
    null,
  );
});

Deno.test("2,5% de R$ 100 entram como R$ 2,50 fixos na subconta", () => {
  assertEquals(
    pointsReserveSplitLine({
      sandbox: true,
      reserveWalletId: "wal_reserva",
      rootWalletId: "wal_raiz",
      houseWalletId: "wal_casa",
      referralCents: 250,
    }),
    { walletId: "wal_reserva", fixedValue: 2.5 },
  );
});

Deno.test("vaga de R$ 100 paga R$ 75 à casa e devolve R$ 25 à raiz", () => {
  assertEquals(
    pointsReserveMoves({ backedCents: 10000, houseOwedCents: 7500 }),
    { houseCents: 7500, platformReturnCents: 2500 },
  );
  assertEquals(
    pointsReserveMoves({ backedCents: 7000, houseOwedCents: 4500 }),
    { houseCents: 4500, platformReturnCents: 2500 },
  );
  assertEquals(backedCentsOf({
    backed_points: 8000,
    points: 10000,
    amount_cents: 10000,
  }), 8000);
});

Deno.test("transferência da reserva recusa produção sem chamar a rede", async () => {
  let called = false;
  await assertRejects(
    () =>
      postSandboxTransfer({
        baseUrl: asaasProductionBaseUrl,
        apiKey: "chave",
        fetchFn: () => {
          called = true;
          return Promise.resolve(new Response(""));
        },
        valueCents: 7500,
        destinationWalletId: "wal_casa",
        externalReference: "reserve:1:house",
      }),
    Error,
    "sandbox",
  );
  assertEquals(called, false);
});

Deno.test("no sandbox a transferência usa a chave da subconta", async () => {
  const seen: { url?: string; key?: string; body?: string } = {};
  const id = await postSandboxTransfer({
    baseUrl: asaasSandboxBaseUrl,
    apiKey: "chave-reserva",
    fetchFn: (url, init) => {
      seen.url = String(url);
      seen.key = new Headers(init?.headers).get("access_token") ?? "";
      seen.body = String(init?.body);
      return Promise.resolve(new Response(JSON.stringify({ id: "tr_1" })));
    },
    valueCents: 7500,
    destinationWalletId: "wal_casa",
    externalReference: "reserve:abc:house",
  });
  assertEquals(id, "tr_1");
  assertEquals(seen.url, `${asaasSandboxBaseUrl}/transfers`);
  assertEquals(seen.key, "chave-reserva");
  assertEquals(
    seen.body,
    JSON.stringify({
      value: 75,
      walletId: "wal_casa",
      externalReference: "reserve:abc:house",
    }),
  );
});

Deno.test("sem permissão de ambiente a reserva fica desligada", () => {
  assertEquals(readEnv({
    get() {
      throw new Error("NotCapable");
    },
  }, "ASAAS_POINTS_RESERVE_WALLET_ID"), "");
});

Deno.test("produção não move a reserva nem anula o crédito", async () => {
  let calls = 0;
  const paid = await settlePointsReservePayout({
    rpc: () => {
      calls += 1;
      return Promise.resolve({ data: "send", error: null });
    },
    baseUrl: asaasProductionBaseUrl,
    reserveApiKey: "chave",
    rootWalletId: "wal_raiz",
    houseWalletId: "wal_casa",
    chargeId: "abc",
    backedCents: 10000,
    houseOwedCents: 7500,
    fetchFn: () => Promise.resolve(new Response("")),
  });
  assertEquals(paid, false);
  assertEquals(calls, 0);
});
