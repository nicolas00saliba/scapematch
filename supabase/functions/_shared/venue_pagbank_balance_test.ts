import { assert, assertEquals } from "jsr:@std/assert@1";
import { readSellerBalance } from "./pagbank_transfers.ts";
import {
  accessFromRpc,
  handleVenuePagbankBalance,
  type VenueAccess,
  type VenuePagbankBalanceDeps,
} from "./venue_pagbank_balance.ts";

const venue = "b1111111-1111-4111-8111-111111111111";
const owner = "a1111111-1111-4111-8111-111111111111";
const access = "access-da-casa";
const refresh = "refresh-da-casa";
const platform = "token-da-plataforma";

Deno.test("o saldo lê disponível, bloqueado e retido em reais", () => {
  const plain = readSellerBalance({ balance: 12.5 });
  assertEquals(plain.availableCents, 1250);
  assertEquals(plain.blockedCents, null);
  assertEquals(plain.heldCents, null);

  const parts = readSellerBalance({
    available: 10,
    blocked: 1.5,
    withheld: 2,
  });
  assertEquals(parts.availableCents, 1000);
  assertEquals(parts.blockedCents, 150);
  assertEquals(parts.heldCents, 200);

  const nested = readSellerBalance({
    available_amount: { value: 8 },
    blocked_amount: { amount: { value: 0 } },
    waiting_funds: 0.5,
  });
  assertEquals(nested.availableCents, 800);
  assertEquals(nested.blockedCents, 0);
  assertEquals(nested.heldCents, 50);

  const list = readSellerBalance({
    balances: [
      { type: "AVAILABLE", amount: 12.5 },
      { type: "BLOCKED", amount: 1 },
      { type: "HELD", amount: 0.25 },
    ],
  });
  assertEquals(list.availableCents, 1250);
  assertEquals(list.blockedCents, 100);
  assertEquals(list.heldCents, 25);
  assertEquals(readSellerBalance({ amount: { value: 10.5 } }).availableCents, 1050);
});

Deno.test("403, 401 e 404 não inventam saldo e não logam o token", async () => {
  for (const status of [401, 403, 404]) {
    const lines: string[] = [];
    const seen: string[] = [];
    const result = await call({
      fetchFn: (_url, init) => {
        seen.push(header(init, "Authorization"));
        return Promise.resolve(new Response("segredo", { status }));
      },
      refresh: () =>
        Promise.resolve({
          accessToken: "access-renovado",
          refreshToken: "refresh-renovado",
          expiresIn: 60,
        }),
      log: lines,
    });
    assertEquals(result.status, 200);
    const body = await result.json();
    assertEquals(body.status, "unavailable");
    assertEquals(body.code, "pagbank_balance_unavailable");
    assertEquals(body.reason, "forbidden");
    assertEquals("available_cents" in body, false);
    assertEquals(seen[0], `Bearer ${access}`);
    assertEquals(seen.length, status === 401 ? 2 : 1);
    const log = lines.join("\n");
    assert(log.includes(`"status":"${status}"`));
    assertEquals(log.includes(access), false);
    assertEquals(log.includes(refresh), false);
    assertEquals(log.includes("access-renovado"), false);
    assertEquals(log.includes(platform), false);
    assertEquals(log.includes("segredo"), false);
  }
});

Deno.test("o 401 renova o token da casa e repete o saldo", async () => {
  const auths: string[] = [];
  const stored: VenueAccess[] = [];
  const lines: string[] = [];
  const result = await call({
    fetchFn: (_url, init) => {
      const auth = header(init, "Authorization");
      auths.push(auth);
      if (auth === `Bearer ${access}`) {
        return Promise.resolve(new Response("", { status: 401 }));
      }
      return Promise.resolve(new Response(JSON.stringify({
        available: 20,
        blocked: 3,
      }), { status: 200 }));
    },
    refresh: () =>
      Promise.resolve({
        accessToken: "access-novo",
        refreshToken: "refresh-novo",
        expiresIn: 3600,
      }),
    storeTokens: (_venueId, tokens) => {
      stored.push(tokens);
      return Promise.resolve();
    },
    log: lines,
  });
  const body = await result.json();
  assertEquals(body, {
    status: "ok",
    available_cents: 2000,
    blocked_cents: 300,
    held_cents: null,
    read_at: new Date(1_700_000_000_000).toISOString(),
  });
  assertEquals(auths, [`Bearer ${access}`, "Bearer access-novo"]);
  assertEquals(stored[0]?.accessToken, "access-novo");
  const encoded = JSON.stringify(body);
  assertEquals(encoded.includes("access-novo"), false);
  assertEquals(encoded.includes(access), false);
  assertEquals(lines.join("\n").includes("access-novo"), false);
});

Deno.test("resposta sem saldo vira indisponível, sem número no log", async () => {
  const lines: string[] = [];
  const result = await call({
    fetchFn: () =>
      Promise.resolve(new Response(JSON.stringify({ foo: 12.555 }), {
        status: 200,
      })),
    log: lines,
  });
  const body = await result.json();
  assertEquals(body.status, "unavailable");
  assertEquals(lines.join("\n").includes("12.555"), false);
  assert(lines.some((line) => line.includes('"code":"balance_shape"')));
});

Deno.test("casa sem token não chama a PagBank", async () => {
  let called = 0;
  const result = await call({
    tokens: null,
    fetchFn: () => {
      called += 1;
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assertEquals(await result.json(), { status: "unlinked" });
  assertEquals(called, 0);
});

Deno.test("outra casa não lê o saldo", async () => {
  let called = 0;
  const result = await call({
    userId: "c1111111-1111-4111-8111-111111111111",
    fetchFn: () => {
      called += 1;
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assertEquals(result.status, 403);
  assertEquals(called, 0);
});

function header(init: RequestInit | undefined, name: string): string {
  const headers = init?.headers;
  if (!headers || Array.isArray(headers) || headers instanceof Headers) return "";
  return (headers as Record<string, string>)[name] ?? "";
}

function call(input: {
  fetchFn?: VenuePagbankBalanceDeps["fetchFn"];
  tokens?: VenueAccess | null;
  userId?: string;
  refresh?: VenuePagbankBalanceDeps["refresh"];
  storeTokens?: VenuePagbankBalanceDeps["storeTokens"];
  log?: string[];
}): Promise<Response> {
  const original = console.error;
  console.error = (line?: unknown) => {
    input.log?.push(String(line ?? ""));
  };
  const deps: VenuePagbankBalanceDeps = {
    env: { get: (name) => name === "PAGBANK_TOKEN" ? platform : "production" },
    fetchFn: input.fetchFn ??
      (() => Promise.resolve(new Response("{}", { status: 200 }))),
    nowMs: 1_700_000_000_000,
    userFrom: () => Promise.resolve({ id: input.userId ?? owner }),
    isAdmin: () => Promise.resolve(false),
    ownerOf: () => Promise.resolve(owner),
    readTokens: () =>
      Promise.resolve(
        input.tokens === undefined
          ? {
            accessToken: access,
            refreshToken: refresh,
            expiresAt: "2099-01-01T00:00:00.000Z",
          }
          : input.tokens,
      ),
    storeTokens: input.storeTokens ?? (() => Promise.resolve()),
    refresh: input.refresh ?? (() => Promise.reject(new Error("não renovar"))),
  };
  const req = new Request("https://example.test/venue-pagbank-balance", {
    method: "POST",
    headers: { Authorization: "Bearer sessao" },
    body: JSON.stringify({ venue_id: venue }),
  });
  return handleVenuePagbankBalance(req, deps).finally(() => {
    console.error = original;
  });
}

Deno.test("o RPC de tokens devolve lista de uma linha e isso conta como conectada", () => {
  const row = {
    access_token: " access-da-casa ",
    refresh_token: "refresh-da-casa",
    access_expires_at: "2027-11-26T17:46:36.330Z",
  };
  const expected = {
    accessToken: access,
    refreshToken: refresh,
    expiresAt: "2027-11-26T17:46:36.330Z",
  };
  assertEquals(accessFromRpc([row]), expected);
  assertEquals(accessFromRpc(row), expected);
  assertEquals(accessFromRpc([]), null);
  assertEquals(accessFromRpc(null), null);
  assertEquals(accessFromRpc([{ access_token: "  " }]), null);
  assertEquals(accessFromRpc([{ access_token: null }]), null);
});

Deno.test("saldo ok traz o horário da leitura e nunca vem do livro", async () => {
  const result = await call({
    fetchFn: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ balances: [{ type: "AVAILABLE", amount: 7.9 }] }),
          { status: 200 },
        ),
      ),
  });
  const body = await result.json();
  assertEquals(body.status, "ok");
  assertEquals(body.available_cents, 790);
  assertEquals(body.read_at, new Date(1_700_000_000_000).toISOString());
});
