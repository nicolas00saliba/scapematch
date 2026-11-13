import { assertEquals, assertRejects } from "jsr:@std/assert";
import { asaasProductionBaseUrl, asaasSandboxBaseUrl } from "./asaas_provider.ts";
import {
  backedCentsOf,
  classifyReserveTransfer,
  fundCashbackReserve,
  pointsReserveMoves,
  pointsReserveSplitLine,
  postReserveTransfer,
  readEnv,
  reserveTransferPageSize,
  settlePointsReservePayout,
} from "./points_reserve_asaas.ts";

Deno.test("sem carteira, centavo inválido ou carteira repetida o split não entra", () => {
  const base = {
    reserveWalletId: "wal_reserva",
    rootWalletId: "wal_raiz",
    houseWalletId: "wal_casa",
    referralCents: 250,
  };
  assertEquals(pointsReserveSplitLine({ ...base, referralCents: 0 }), null);
  assertEquals(pointsReserveSplitLine({ ...base, referralCents: 1.5 }), null);
  assertEquals(
    pointsReserveSplitLine({ ...base, reserveWalletId: "wal_raiz" }),
    null,
  );
  assertEquals(
    pointsReserveSplitLine({ ...base, reserveWalletId: "wal_casa" }),
    null,
  );
  assertEquals(pointsReserveSplitLine({ ...base, reserveWalletId: "" }), null);
});

Deno.test("2,5% de R$ 100 entram como R$ 2,50 fixos na subconta", () => {
  assertEquals(
    pointsReserveSplitLine({
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

Deno.test("URL que não é a API Asaas não chama a rede", async () => {
  let called = false;
  await assertRejects(
    () =>
      postReserveTransfer({
        baseUrl: "https://api.asaas.com.evil.com/v3",
        apiKey: "chave",
        fetchFn: () => {
          called = true;
          return Promise.resolve(new Response(""));
        },
        valueCents: 7500,
        destinationWalletId: "wal_casa",
        externalReference: "reserve:abc:house",
        createdOn: "2026-11-13",
      }),
    Error,
    "Asaas",
  );
  assertEquals(called, false);
});

Deno.test("produção transfere o valor exato e a repetição não cria outra", async () => {
  let posts = 0;
  const reference = "reserve:abc:house";
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    if (method === "GET") {
      const parsed = new URL(String(url));
      assertEquals(parsed.searchParams.get("externalReference"), null);
      assertEquals(parsed.searchParams.get("dateCreated[ge]"), "2026-11-13");
      const data = posts === 0
        ? []
        : [{
          id: "tr_prod",
          externalReference: reference,
          status: "DONE",
          value: 75,
        }];
      return Promise.resolve(new Response(JSON.stringify({ data, hasMore: false })));
    }
    posts += 1;
    const body = JSON.parse(String(init?.body));
    assertEquals(body, {
      value: 75,
      walletId: "wal_casa",
      externalReference: reference,
    });
    assertEquals(String(url), `${asaasProductionBaseUrl}/transfers`);
    assertEquals(new Headers(init?.headers).get("access_token"), "chave-reserva");
    return Promise.resolve(new Response(JSON.stringify({
      id: "tr_prod",
      status: "DONE",
      value: 75,
      externalReference: reference,
    })));
  };
  const input = {
    baseUrl: asaasProductionBaseUrl,
    apiKey: "chave-reserva",
    fetchFn,
    valueCents: 7500,
    destinationWalletId: "wal_casa",
    externalReference: reference,
    createdOn: "2026-11-13",
  };
  assertEquals(await postReserveTransfer(input), { id: "tr_prod", state: "paid" });
  assertEquals(await postReserveTransfer(input), { id: "tr_prod", state: "paid" });
  assertEquals(posts, 1);
});

Deno.test("a transferência certa na segunda página não cria outra", async () => {
  const reference = "reserve:abc:house";
  let posts = 0;
  const hit = await postReserveTransfer({
    baseUrl: asaasProductionBaseUrl,
    apiKey: "chave-reserva",
    fetchFn: (url, init) => {
      if ((init?.method ?? "GET") === "POST") {
        posts += 1;
        return Promise.resolve(new Response("{}"));
      }
      const parsed = new URL(String(url));
      assertEquals(parsed.searchParams.get("externalReference"), null);
      assertEquals(parsed.searchParams.get("dateCreated[ge]"), "2026-11-13");
      assertEquals(parsed.searchParams.get("limit"), String(reserveTransferPageSize));
      const offset = Number(parsed.searchParams.get("offset"));
      if (offset === 0) {
        const data = Array.from({ length: reserveTransferPageSize }, (_, index) => ({
          id: `tr_${index}`,
          externalReference: `outra:${index}`,
          status: "DONE",
          value: 1,
        }));
        return Promise.resolve(new Response(JSON.stringify({
          data,
          hasMore: true,
          limit: reserveTransferPageSize,
          offset: 0,
        })));
      }
      assertEquals(offset, reserveTransferPageSize);
      return Promise.resolve(new Response(JSON.stringify({
        data: [{
          id: "tr_certa",
          externalReference: reference,
          status: "DONE",
          value: 75,
        }],
        hasMore: false,
        limit: reserveTransferPageSize,
        offset,
      })));
    },
    valueCents: 7500,
    destinationWalletId: "wal_casa",
    externalReference: reference,
    createdOn: "2026-11-13",
  });
  assertEquals(hit, { id: "tr_certa", state: "paid" });
  assertEquals(posts, 0);
});

Deno.test("token pendente não conta como transferência paga", () => {
  assertEquals(
    classifyReserveTransfer({
      id: "tr_auth",
      status: "AWAITING_CRITICAL_ACTION_AUTHORIZATION",
      authorized: false,
      value: 75,
    }, 7500),
    { id: "tr_auth", state: "awaiting_authorization" },
  );
  assertEquals(
    classifyReserveTransfer({
      id: "tr_sms",
      status: "PENDING",
      authorized: false,
      value: 75,
    }, 7500),
    { id: "tr_sms", state: "awaiting_authorization" },
  );
  assertEquals(
    classifyReserveTransfer({ id: "tr_ok", status: "DONE", value: 75 }, 7500),
    { id: "tr_ok", state: "paid" },
  );
});

Deno.test("no sandbox a transferência usa a chave da subconta", async () => {
  const seen: { url?: string; key?: string; body?: string } = {};
  const id = await postReserveTransfer({
    baseUrl: asaasSandboxBaseUrl,
    apiKey: "chave-reserva",
    fetchFn: (url, init) => {
      if ((init?.method ?? "GET") === "GET") {
        return Promise.resolve(new Response(JSON.stringify({ data: [] })));
      }
      seen.url = String(url);
      seen.key = new Headers(init?.headers).get("access_token") ?? "";
      seen.body = String(init?.body);
      return Promise.resolve(new Response(JSON.stringify({
        id: "tr_1",
        status: "DONE",
        value: 75,
      })));
    },
    valueCents: 7500,
    destinationWalletId: "wal_casa",
    externalReference: "reserve:abc:house",
    createdOn: "2026-11-13",
  });
  assertEquals(id, { id: "tr_1", state: "paid" });
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

Deno.test("host parecido não move a reserva nem anula o crédito", async () => {
  let calls = 0;
  const paid = await settlePointsReservePayout({
    rpc: () => {
      calls += 1;
      return Promise.resolve({ data: "send", error: null });
    },
    baseUrl: "https://api.asaas.com.evil.com/v3",
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

Deno.test("produção paga a casa uma vez; repetição acha a transferência", async () => {
  let posts = 0;
  const reference = "reserve:abc:house";
  const rpc = (fn: string) => {
    if (fn === "claim_points_reserve_transfer") {
      return Promise.resolve({ data: posts === 0 ? "send" : "skip", error: null });
    }
    if (fn === "points_reserve_transfer_anchor") {
      return Promise.resolve({ data: "2026-11-13", error: null });
    }
    return Promise.resolve({ data: null, error: null });
  };
  const fetchFn = (url: string, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    if (method === "POST") {
      posts += 1;
      const body = JSON.parse(String(init?.body));
      assertEquals(body.value, 75);
      assertEquals(body.walletId, "wal_casa");
      assertEquals(String(url), `${asaasProductionBaseUrl}/transfers`);
      return Promise.resolve(new Response(JSON.stringify({
        id: "tr_casa",
        status: "DONE",
        value: 75,
        externalReference: reference,
      })));
    }
    const parsed = new URL(String(url));
    assertEquals(parsed.searchParams.get("externalReference"), null);
    assertEquals(parsed.searchParams.get("dateCreated[ge]"), "2026-11-13");
    const data = posts === 0
      ? []
      : [{ id: "tr_casa", externalReference: reference, status: "DONE", value: 75 }];
    return Promise.resolve(new Response(JSON.stringify({ data, hasMore: false })));
  };
  const input = {
    rpc,
    baseUrl: asaasProductionBaseUrl,
    reserveApiKey: "chave",
    rootWalletId: "wal_raiz",
    houseWalletId: "wal_casa",
    chargeId: "abc",
    backedCents: 7500,
    houseOwedCents: 7500,
    fetchFn,
  };
  assertEquals(await settlePointsReservePayout(input), true);
  assertEquals(await settlePointsReservePayout(input), true);
  assertEquals(posts, 1);
});

Deno.test("autorização de evento crítico não liquida e não transfere de novo", async () => {
  const reference = "reserve:abc:house";
  const notes: string[] = [];
  const logs: string[] = [];
  const original = console.error;
  console.error = (line?: unknown) => {
    logs.push(String(line));
  };
  let posts = 0;
  try {
    const rpc = (fn: string, args: Record<string, unknown>) => {
      if (fn === "claim_points_reserve_transfer") {
        return Promise.resolve({ data: posts === 0 ? "send" : "skip", error: null });
      }
      if (fn === "points_reserve_transfer_anchor") {
        return Promise.resolve({ data: "2026-11-13", error: null });
      }
      if (fn === "note_points_reserve_awaiting") {
        notes.push(String(args.p_provider_ref));
        return Promise.resolve({ data: null, error: null });
      }
      if (fn === "complete_points_reserve_transfer" && args.p_ok === true) {
        return Promise.resolve({ data: null, error: { message: "nao liquidar" } });
      }
      return Promise.resolve({ data: null, error: null });
    };
    const fetchFn = (url: string, init?: RequestInit) => {
      if ((init?.method ?? "GET") === "POST") {
        posts += 1;
        return Promise.resolve(new Response(JSON.stringify({
          id: "tr_auth",
          status: "AWAITING_CRITICAL_ACTION_AUTHORIZATION",
          authorized: false,
          value: 75,
          externalReference: reference,
        })));
      }
      const offset = Number(new URL(String(url)).searchParams.get("offset"));
      if (posts === 0 || offset === 0) {
        const data = Array.from({ length: reserveTransferPageSize }, (_, index) => ({
          id: `tr_${index}`,
          externalReference: `outra:${index}`,
          status: "DONE",
          value: 1,
        }));
        return Promise.resolve(new Response(JSON.stringify({
          data,
          hasMore: posts > 0,
          offset,
        })));
      }
      return Promise.resolve(new Response(JSON.stringify({
        data: [{
          id: "tr_auth",
          externalReference: reference,
          status: "AWAITING_CRITICAL_ACTION_AUTHORIZATION",
          authorized: false,
          value: 75,
        }],
        hasMore: false,
        offset,
      })));
    };
    const input = {
      rpc,
      baseUrl: asaasProductionBaseUrl,
      reserveApiKey: "chave",
      rootWalletId: "wal_raiz",
      houseWalletId: "wal_casa",
      chargeId: "abc",
      backedCents: 7500,
      houseOwedCents: 7500,
      fetchFn,
    };
    assertEquals(await settlePointsReservePayout(input), false);
    assertEquals(await settlePointsReservePayout(input), false);
    assertEquals(posts, 1);
    assertEquals(notes, ["tr_auth", "tr_auth"]);
    assertEquals(logs.some((line) => line.includes("chave")), false);
    assertEquals(
      logs.filter((line) => line.includes("awaiting_critical_action_authorization")).length,
      2,
    );
  } finally {
    console.error = original;
  }
});

Deno.test("cashback entra na subconta pela conta raiz na API oficial", async () => {
  let calls = 0;
  await fundCashbackReserve(
    { rpc: () => {
      calls += 1;
      return Promise.resolve({ data: [], error: null });
    } },
    {
      get: (name) =>
        name === "ASAAS_BASE_URL" ? "https://evil.example/v3" : "x",
    },
    "charge-1",
  );
  assertEquals(calls, 0);

  const seen: { key?: string; body?: string } = {};
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls += 1;
    if (fn === "cashback_reserve_pending") {
      return Promise.resolve({
        data: [{ purpose: "cashback_in", amount_cents: 250 }],
        error: null,
      });
    }
    if (fn === "claim_points_reserve_transfer") {
      assertEquals(args.p_purpose, "cashback_in");
      assertEquals(args.p_amount_cents, 250);
      assertEquals(args.p_wallet_id, "wal_reserva");
      return Promise.resolve({ data: "send", error: null });
    }
    if (fn === "points_reserve_transfer_anchor") {
      return Promise.resolve({ data: "2026-11-13", error: null });
    }
    return Promise.resolve({ data: null, error: null });
  };
  await fundCashbackReserve(
    { rpc },
    {
      get: (name) => {
        if (name === "ASAAS_BASE_URL") return asaasSandboxBaseUrl;
        if (name === "ASAAS_API_KEY") return "chave-raiz";
        if (name === "ASAAS_POINTS_RESERVE_WALLET_ID") return "wal_reserva";
        if (name === "ASAAS_ROOT_WALLET_ID") return "wal_raiz";
        return "";
      },
    },
    "charge-2",
    (url, init) => {
      if ((init?.method ?? "GET") === "GET") {
        return Promise.resolve(new Response(JSON.stringify({ data: [] })));
      }
      seen.key = new Headers(init?.headers).get("access_token") ?? "";
      seen.body = String(init?.body);
      assertEquals(String(url), `${asaasSandboxBaseUrl}/transfers`);
      return Promise.resolve(new Response(JSON.stringify({
        id: "tr_cb",
        status: "DONE",
        value: 2.5,
      })));
    },
  );
  assertEquals(seen.key, "chave-raiz");
  assertEquals(
    seen.body,
    JSON.stringify({
      value: 2.5,
      walletId: "wal_reserva",
      externalReference: "reserve:charge-2:cashback_in",
    }),
  );
});
