import { assertEquals } from "jsr:@std/assert@1";
import {
  handleVenueDocuments,
  officialAsaasBase,
  roleOf,
  safeOnboardingUrl,
  type DocumentAccess,
  type DocumentRoleStore,
  type VenueDocumentDeps,
} from "./venue_documents.ts";

const venueId = "11111111-1111-4111-8111-111111111111";

Deno.test("documento não abre site de provedor", async () => {
  assertEquals(officialAsaasBase("https://api.asaas.com/v3"), null);
  assertEquals(safeOnboardingUrl("https://cadastro.io/x"), null);
  const calls: string[] = [];
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }, "aaa.bbb.ccc"),
    deps({
      fetchFn: (url: string) => {
        calls.push(url);
        return Promise.resolve(new Response("{}"));
      },
      role: "owner",
      strong: true,
    }),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.onboarding_url, null);
  assertEquals(body.documents, []);
  assertEquals(calls, []);
});

Deno.test("sem sessão, sem papel ou sem reautenticação não consulta provedor", async () => {
  let called = false;
  const fetchFn = () => {
    called = true;
    return Promise.resolve(new Response(""));
  };
  const missing = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }, ""),
    deps({ fetchFn, actorId: "" }),
  );
  assertEquals(missing.status, 401);
  assertEquals((await missing.json()).error, "not authenticated");
  const staff = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }),
    deps({ fetchFn, role: "none" }),
  );
  assertEquals(staff.status, 403);
  assertEquals((await staff.json()).error, "not owner");
  const reauth = await handleVenueDocuments(
    request({
      action: "upload",
      venue_id: venueId,
      document_id: "doc_sem_link_1",
    }),
    deps({ fetchFn, strong: false }),
  );
  assertEquals(reauth.status, 401);
  assertEquals((await reauth.json()).error, "reauth");
  assertEquals(called, false);
});

Deno.test("admin sem MFA não lista nem executa outra ação", async () => {
  let called = false;
  const fetchFn = () => {
    called = true;
    return Promise.resolve(new Response(""));
  };
  const store = roleStore({ admin: true });
  const jwt = sessionJwt("aal1");
  for (const action of ["list", "upload", "remove"]) {
    const response = await handleVenueDocuments(
      request({
        action,
        venue_id: venueId,
        document_id: "doc_sem_link_1",
      }, jwt),
      deps({
        fetchFn,
        strong: true,
        role: (id, userId, token) => roleOf(store, id, userId, token),
      }),
    );
    assertEquals(response.status, 403);
    assertEquals(await response.json(), { error: "not owner" });
  }
  assertEquals(called, false);
  assertEquals(store.adminChecks, 0);
});

function sessionJwt(aal: string): string {
  const payload = btoa(JSON.stringify({ sub: "user-1", aal }))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `h.${payload}.s`;
}

function roleStore(input: {
  snapshotRole?: string;
  admin?: boolean;
}): DocumentRoleStore & { adminChecks: number; asAdmin: boolean } {
  const store = {
    adminChecks: 0,
    asAdmin: false,
    rpc(_fn: string, args: Record<string, unknown>) {
      store.asAdmin = args.p_as_admin === true;
      return Promise.resolve({ role: input.snapshotRole ?? "" });
    },
    isAdmin() {
      store.adminChecks += 1;
      return Promise.resolve(input.admin ?? false);
    },
  };
  return store;
}

function request(body: Record<string, unknown>, jwt = "token"): Request {
  return new Request("https://example.test/venue-documents", {
    method: "POST",
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
    body: JSON.stringify(body),
  });
}

function deps(input: {
  fetchFn: VenueDocumentDeps["fetchFn"];
  role?: DocumentAccess | VenueDocumentDeps["role"];
  actorId?: string;
  strong?: boolean;
}): VenueDocumentDeps {
  const role = input.role ?? "owner";
  return {
    env: { get: () => "" },
    fetchFn: input.fetchFn,
    actor: () =>
      Promise.resolve(
        input.actorId === "" ? null : { id: input.actorId ?? "user-1" },
      ),
    role: typeof role === "function" ? role : () => Promise.resolve(role),
    subaccount: () => Promise.resolve({ apiKey: "", walletId: "" }),
    strongAuth: () => Promise.resolve(input.strong ?? false),
  };
}
