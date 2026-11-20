import { assertEquals } from "jsr:@std/assert@1";
import {
  handleVenueDocuments,
  officialAsaasBase,
  safeOnboardingUrl,
} from "./venue_documents.ts";

Deno.test("documento não abre site de provedor", async () => {
  assertEquals(officialAsaasBase("https://api.asaas.com/v3"), null);
  assertEquals(safeOnboardingUrl("https://cadastro.io/x"), null);
  const calls: string[] = [];
  const response = await handleVenueDocuments(
    new Request("https://example.test/docs", {
      method: "POST",
      headers: { authorization: "Bearer aaa.bbb.ccc" },
      body: JSON.stringify({
        action: "list",
        venue_id: "11111111-1111-4111-8111-111111111111",
      }),
    }),
    {
      env: { get: () => "" },
      fetchFn: (url: string) => {
        calls.push(url);
        return Promise.resolve(new Response("{}"));
      },
      actor: () => Promise.resolve({ id: "user-1" }),
      role: () => Promise.resolve("owner"),
      strongAuth: () => Promise.resolve(true),
      subaccount: () => Promise.resolve({ apiKey: "", walletId: "" }),
    } as never,
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.onboarding_url, null);
  assertEquals(body.documents, []);
  assertEquals(calls, []);
});
