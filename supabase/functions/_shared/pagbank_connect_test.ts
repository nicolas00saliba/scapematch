import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { PagBankProvider, pagbankProductionBaseUrl } from "./pagbank_provider.ts";
import { PagbankAccountConflict } from "./pagbank_binding.ts";
import {
  completePagbankConnect,
  connectRedirectUri,
  freshConnectAccess,
} from "./pagbank_connect.ts";

const venue = "b1111111-1111-4111-8111-111111111111";
const user = "a1111111-1111-4111-8111-111111111111";
const state = "ab".repeat(32);

Deno.test("o redirect do admin não aceita URI fora da env", () => {
  const partner = "https://parceiro.escapematch.com.br/pagbank/retorno";
  assertEquals(
    connectRedirectUri({ partner, admin: "", surface: "parceiro" }),
    partner,
  );
  assertEquals(
    connectRedirectUri({
      partner,
      admin: "https://admin.escapematch.com.br/pagbank/retorno",
      surface: "admin",
    }),
    "https://admin.escapematch.com.br/pagbank/retorno",
  );
  assertEquals(
    connectRedirectUri({ partner, admin: "http://admin.example", surface: "admin" }),
    partner,
  );
});

Deno.test("o state do connect não é o id da casa", () => {
  const url = new PagBankProvider(
    "tok",
    pagbankProductionBaseUrl,
    () => Promise.resolve(new Response("{}", { status: 200 })),
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  ).connectAuthorizeUrl({
    clientId: "client",
    redirectUri: "https://parceiro.escapematch.com.br/pagbank/retorno",
    state,
  });
  const parsed = new URL(url);
  assertEquals(parsed.searchParams.get("state"), state);
  assertEquals(parsed.searchParams.get("state") === venue, false);
  assertEquals(url.includes(venue), false);
});

Deno.test("code sem state válido não troca token", async () => {
  let exchanged = 0;
  await assertRejects(
    () =>
      completePagbankConnect({
        userId: user,
        code: "code-1",
        state: venue,
        consume: () => Promise.resolve(null),
        exchange: () => {
          exchanged += 1;
          return Promise.resolve({
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 60,
            accountId: "ACCO_1",
          });
        },
        link: () => Promise.resolve(),
      }),
    Error,
    "state",
  );
  assertEquals(exchanged, 0);
});

Deno.test("o retorno grava o refresh token e não devolve o access", async () => {
  const saved: { refresh: string; expires: string | null }[] = [];
  const accounts: string[] = [];
  const done = await completePagbankConnect({
    userId: user,
    code: "code-1",
    state,
    nowMs: 1_700_000_000_000,
    consume: (gotState, gotUser) => {
      assertEquals(gotState, state);
      assertEquals(gotUser, user);
      return Promise.resolve({
        venueId: venue,
        redirectUri: "https://parceiro.escapematch.com.br/pagbank/retorno",
      });
    },
    exchange: (_code, redirect) => {
      assertEquals(
        redirect,
        "https://parceiro.escapematch.com.br/pagbank/retorno",
      );
      return Promise.resolve({
        accessToken: "access-secreto",
        refreshToken: "refresh-secreto",
        expiresIn: 120,
        accountId: "ACCO_CASA",
      });
    },
    link: (_venueId, accountId, tokens) => {
      accounts.push(accountId);
      saved.push({ refresh: tokens.refreshToken, expires: tokens.expiresAt });
      return Promise.resolve();
    },
  });
  assertEquals(done.venueId, venue);
  assertEquals(accounts, ["ACCO_CASA"]);
  assertEquals(saved[0].refresh, "refresh-secreto");
  assert(saved[0].expires);
  assertEquals(JSON.stringify(done).includes("access-secreto"), false);
});

Deno.test("renova o access antes de vencer e no 401", async () => {
  const now = 1_700_000_000_000;
  let calls = 0;
  const early = await freshConnectAccess({
    accessToken: "velho",
    refreshToken: "refresh-1",
    expiresAtMs: now + 30_000,
    nowMs: now,
    refresh: () => {
      calls += 1;
      return Promise.resolve({
        accessToken: "novo",
        refreshToken: "refresh-2",
        expiresIn: 3600,
      });
    },
  });
  assertEquals(early.refreshed, true);
  assertEquals(early.accessToken, "novo");
  assertEquals(early.refreshToken, "refresh-2");
  assertEquals(calls, 1);

  const later = await freshConnectAccess({
    accessToken: "novo",
    refreshToken: "refresh-2",
    expiresAtMs: now + 3_600_000,
    nowMs: now,
    refresh: () => Promise.reject(new Error("não devia")),
  });
  assertEquals(later.refreshed, false);

  const callsHttp: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    callsHttp.push(`${init?.method ?? "GET"} ${url}`);
    const auth = (init?.headers as Record<string, string>).Authorization;
    if (auth === "Bearer velho") {
      return Promise.resolve(new Response("{}", { status: 401 }));
    }
    if (url.endsWith("/oauth2/token")) {
      return Promise.resolve(new Response(JSON.stringify({
        access_token: "novo",
        refresh_token: "refresh-2",
        expires_in: 3600,
      }), { status: 200 }));
    }
    return Promise.resolve(new Response(JSON.stringify({
      balance: 1000,
    }), { status: 200 }));
  };
  const venueClient = new PagBankProvider(
    "velho",
    pagbankProductionBaseUrl,
    fetchFn,
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  const platform = new PagBankProvider(
    "plataforma",
    pagbankProductionBaseUrl,
    fetchFn,
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  venueClient.bindAccessRefresh(async () => {
    const next = await platform.refreshConnectToken({
      clientId: "client",
      clientSecret: "secret",
      refreshToken: "refresh-1",
    });
    return next.accessToken;
  });
  const balance = await venueClient.financeBalanceCents();
  assertEquals(balance, 100_000);
  assert(callsHttp.some((call) => call.includes("/oauth2/token")));
  assert(callsHttp.filter((call) => call.includes("/accounts/balance")).length >= 1);
});

Deno.test("segunda conta na mesma casa é recusada e nada é gravado fora do link", async () => {
  const linked: string[] = [];
  let existing: string | null = "ACCO_PRIMEIRA";
  const attempt = (account: string) =>
    completePagbankConnect({
      userId: user,
      code: "code-2",
      state,
      consume: () =>
        Promise.resolve({
          venueId: venue,
          redirectUri: "https://parceiro.escapematch.com.br/pagbank/retorno",
        }),
      exchange: () =>
        Promise.resolve({
          accessToken: "a",
          refreshToken: "r",
          expiresIn: 60,
          accountId: account,
        }),
      link: (_venueId, accountId) => {
        if (existing && existing !== accountId) {
          throw new PagbankAccountConflict("pagbank_account_exists");
        }
        existing = accountId;
        linked.push(accountId);
        return Promise.resolve();
      },
    });
  await assertRejects(
    () => attempt("ACCO_SEGUNDA"),
    PagbankAccountConflict,
    "pagbank_account_exists",
  );
  assertEquals(linked, []);
  assertEquals(existing, "ACCO_PRIMEIRA");
  await attempt("ACCO_PRIMEIRA");
  assertEquals(linked, ["ACCO_PRIMEIRA"]);
});
