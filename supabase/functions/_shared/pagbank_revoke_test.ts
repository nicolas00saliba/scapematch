import { assert, assertEquals } from "jsr:@std/assert@1";
import { revokeConnectTokens } from "./pagbank_revoke.ts";
import { PagBankProvider, pagbankProductionBaseUrl } from "./pagbank_provider.ts";

Deno.test("revoga refresh e depois access; erro não lança", async () => {
  const seen: string[] = [];
  const result = await revokeConnectTokens(
    (input) => {
      seen.push(input.hint);
      return input.hint === "refresh_token"
        ? Promise.reject(new Error("PagBank 400: token_is_no_longer_active"))
        : Promise.resolve();
    },
    { accessToken: "acc", refreshToken: "ref" },
  );
  assertEquals(seen, ["refresh_token", "access_token"]);
  assertEquals(result, { attempted: 2, revoked: 1, failed: 1 });
});

Deno.test("sem token não chama o PagBank", async () => {
  let calls = 0;
  const result = await revokeConnectTokens(
    () => {
      calls += 1;
      return Promise.resolve();
    },
    { accessToken: "", refreshToken: null },
  );
  assertEquals(calls, 0);
  assertEquals(result.attempted, 0);
});

Deno.test("revokeConnectToken chama /oauth2/revoke com os headers do app", async () => {
  let url = "";
  let init: RequestInit | undefined;
  const provider = new PagBankProvider(
    "plataforma",
    pagbankProductionBaseUrl,
    (input, options) => {
      url = String(input);
      init = options;
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  await provider.revokeConnectToken({
    clientId: "cid",
    clientSecret: "csecret",
    bearerToken: "acc-da-casa",
    token: "ref-da-casa",
    hint: "refresh_token",
  });
  assertEquals(url, `${pagbankProductionBaseUrl}/oauth2/revoke`);
  const headers = init?.headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer acc-da-casa");
  assertEquals(headers.X_CLIENT_ID, "cid");
  assertEquals(headers.X_CLIENT_SECRET, "csecret");
  assertEquals(JSON.parse(String(init?.body)), {
    token_type_hint: "refresh_token",
    token: "ref-da-casa",
  });
});

Deno.test("recusa do PagBank na revogação lança sem repetir o token", async () => {
  const provider = new PagBankProvider(
    "plataforma",
    pagbankProductionBaseUrl,
    () => Promise.resolve(new Response('{"error":"invalid_token"}', { status: 400 })),
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  let message = "";
  try {
    await provider.revokeConnectToken({
      clientId: "cid",
      clientSecret: "csecret",
      bearerToken: "acc-secreto",
      token: "acc-secreto",
      hint: "access_token",
    });
  } catch (error) {
    message = (error as Error).message;
  }
  assert(message.startsWith("PagBank 400"));
  assert(!message.includes("acc-secreto"));
});
