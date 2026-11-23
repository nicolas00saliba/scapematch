import { assertEquals } from "jsr:@std/assert";
import { asaasProductionBaseUrl, asaasSandboxBaseUrl } from "./asaas_provider.ts";
import {
  decodeDocumentPayload,
  handleVenueDocuments,
  officialAsaasBase,
  presentDocuments,
  roleOf,
  safeOnboardingUrl,
  type DocumentAccess,
  type DocumentRoleStore,
  type VenueDocumentDeps,
} from "./venue_documents.ts";

const venueId = "11111111-1111-4111-8111-111111111111";
const secret = "super-secret-key";

Deno.test("o link de onboarding só abre host do Asaas em https", () => {
  assertEquals(
    safeOnboardingUrl("https://cadastro.io/8ad196"),
    "https://cadastro.io/8ad196",
  );
  assertEquals(
    safeOnboardingUrl("https://www.asaas.com/onboarding/abc"),
    "https://www.asaas.com/onboarding/abc",
  );
  assertEquals(safeOnboardingUrl("http://cadastro.io/abc"), null);
  assertEquals(safeOnboardingUrl("https://cadastro.io.evil.com/abc"), null);
  assertEquals(safeOnboardingUrl("https://evil.com/?x=cadastro.io"), null);
  assertEquals(safeOnboardingUrl("javascript:alert(1)"), null);
  assertEquals(
    officialAsaasBase(`${asaasProductionBaseUrl}/`),
    asaasProductionBaseUrl,
  );
  assertEquals(officialAsaasBase("https://api.asaas.com.evil.com/v3"), null);
});

Deno.test("com onboardingUrl o grupo não aceita upload pela API", () => {
  const view = presentDocuments(
    { documentation: "PENDING", general: "PENDING" },
    {
      data: [{
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        status: "NOT_SENT",
        type: "IDENTIFICATION",
        title: "Identificação",
        description: "Envie pelo link",
        onboardingUrl: "https://cadastro.io/casa",
      }],
    },
  );
  assertEquals(view.approved, false);
  assertEquals(view.known, true);
  assertEquals(view.onboarding_url, "https://cadastro.io/casa");
  assertEquals(view.documents[0].hosted, true);
  assertEquals(view.documents[0].upload, false);
});

Deno.test("link estranho não volta e também não libera upload", () => {
  const view = presentDocuments(
    { documentation: "PENDING", general: "AWAITING_APPROVAL" },
    {
      data: [{
        id: "doc_sem_link_1",
        status: "NOT_SENT",
        type: "IDENTIFICATION",
        onboardingUrl: "https://evil.example/roubo",
        description: "fale com a@casa.com",
      }],
    },
  );
  assertEquals(view.documents[0].onboarding_url, null);
  assertEquals(view.documents[0].hosted, true);
  assertEquals(view.documents[0].upload, false);
  assertEquals(view.documents[0].description, "");
});

Deno.test("sem link, documento recusado pode ser reenviado", () => {
  const view = presentDocuments(
    {
      documentation: "APPROVED",
      general: "APPROVED",
      commercialInfo: "APPROVED",
      bankAccountInfo: "APPROVED",
    },
    {
      data: [{
        id: "doc_sem_link_1",
        status: "REJECTED",
        type: "IDENTIFICATION",
        title: "RG",
      }],
    },
  );
  assertEquals(view.approved, true);
  assertEquals(view.documents[0].upload, true);
});

Deno.test("a lista usa a chave da subconta e não a devolve", async () => {
  const seen: { url?: string; key?: string } = {};
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }),
    deps({
      fetchFn: (url, init) => {
        seen.url = String(url);
        seen.key = new Headers(init?.headers).get("access_token") ?? "";
        const path = String(url);
        if (path.endsWith("/myAccount/status")) {
          return jsonResponse({
            documentation: "APPROVED",
            general: "APPROVED",
          });
        }
        return jsonResponse({
          data: [{
            id: "doc_sem_link_1",
            status: "APPROVED",
            type: "IDENTIFICATION",
            title: "RG",
          }],
        });
      },
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.approved, true);
  assertEquals(seen.key, secret);
  assertEquals(seen.url, `${asaasSandboxBaseUrl}/myAccount/documents`);
  assertEquals(JSON.stringify(body).includes(secret), false);
});

Deno.test("com link hospedado o upload não chama o POST", async () => {
  const methods: string[] = [];
  const response = await handleVenueDocuments(
    request({
      action: "upload",
      venue_id: venueId,
      document_id: "doc_sem_link_1",
      content_base64: png(),
    }),
    deps({
      strong: true,
      fetchFn: (url, init) => {
        methods.push(init?.method ?? "GET");
        assertEquals(String(url).includes("/myAccount/documents/"), false);
        return jsonResponse({
          documentation: "PENDING",
          general: "PENDING",
          data: [{
            id: "doc_sem_link_1",
            status: "NOT_SENT",
            type: "IDENTIFICATION",
            onboardingUrl: "https://cadastro.io/casa",
          }],
        });
      },
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 409);
  assertEquals(body.error, "onboarding");
  assertEquals(body.onboarding_url, "https://cadastro.io/casa");
  assertEquals(methods.includes("POST"), false);
  assertEquals(JSON.stringify(body).includes(secret), false);
});

Deno.test("sem link o arquivo segue em multipart e o erro não vaza a chave", async () => {
  const posts: { type?: string; file?: string; key?: string }[] = [];
  let posted = false;
  const response = await handleVenueDocuments(
    request({
      action: "upload",
      venue_id: venueId,
      document_id: "doc_sem_link_1",
      content_base64: png(),
    }),
    deps({
      strong: true,
      base: asaasProductionBaseUrl,
      fetchFn: async (url, init) => {
        const method = init?.method ?? "GET";
        const path = String(url);
        if (method === "POST") {
          posted = true;
          const form = init?.body as FormData;
          const file = form.get("documentFile");
          posts.push({
            type: String(form.get("type")),
            file: file instanceof File ? file.name : "",
            key: new Headers(init?.headers).get("access_token") ?? "",
          });
          assertEquals(
            path,
            `${asaasProductionBaseUrl}/myAccount/documents/doc_sem_link_1`,
          );
          return new Response(JSON.stringify({
            errors: [{ description: secret }],
          }), { status: 400 });
        }
        if (path.endsWith("/status")) {
          return jsonResponse({
            documentation: posted ? "AWAITING_APPROVAL" : "PENDING",
            general: "PENDING",
          });
        }
        return jsonResponse({
          data: [{
            id: "doc_sem_link_1",
            status: posted ? "PENDING" : "NOT_SENT",
            type: "IDENTIFICATION",
            title: "RG",
          }],
        });
      },
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body, { error: "asaas_unavailable" });
  assertEquals(posts, [{
    type: "IDENTIFICATION",
    file: "documento.png",
    key: secret,
  }]);
  assertEquals(JSON.stringify(body).includes(secret), false);
});

Deno.test("arquivo que não é pdf nem imagem não sai da função", async () => {
  let called = false;
  const response = await handleVenueDocuments(
    request({
      action: "upload",
      venue_id: venueId,
      document_id: "doc_sem_link_1",
      content_base64: btoa("<html>"),
    }),
    deps({
      strong: true,
      fetchFn: () => {
        called = true;
        return Promise.resolve(new Response(""));
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(called, false);
  assertEquals(decodeDocumentPayload("%%%"), null);
  assertEquals(decodeDocumentPayload(""), null);
});

Deno.test("sem sessão, sem papel ou sem reautenticação não consulta o Asaas", async () => {
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
  const staff = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }),
    deps({ fetchFn, role: "none" }),
  );
  assertEquals(staff.status, 403);
  const reauth = await handleVenueDocuments(
    request({
      action: "upload",
      venue_id: venueId,
      document_id: "doc_sem_link_1",
      content_base64: png(),
    }),
    deps({ fetchFn, strong: false }),
  );
  assertEquals(reauth.status, 401);
  assertEquals(called, false);
});

Deno.test("URL que não é a API oficial não é chamada", async () => {
  let called = false;
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }),
    deps({
      base: "https://api.asaas.com.evil.com/v3",
      fetchFn: () => {
        called = true;
        return Promise.resolve(new Response(""));
      },
    }),
  );
  assertEquals(response.status, 503);
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
        content_base64: png(),
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

Deno.test("admin com aal2 lista os documentos", async () => {
  const store = roleStore({ admin: true });
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }, sessionJwt("aal2")),
    deps({
      fetchFn: asaasDocuments(),
      role: (id, userId, token) => roleOf(store, id, userId, token),
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.approved, true);
  assertEquals(store.adminChecks, 1);
  assertEquals(store.asAdmin, false);
});

Deno.test("o dono da casa lista sem MFA", async () => {
  const store = roleStore({ snapshotRole: "owner", admin: false });
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }, sessionJwt("aal1")),
    deps({
      fetchFn: asaasDocuments(),
      role: (id, userId, token) => roleOf(store, id, userId, token),
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.approved, true);
  assertEquals(store.adminChecks, 0);
});

Deno.test("a reserva de pontos não consulta documentos", async () => {
  let called = false;
  const response = await handleVenueDocuments(
    request({ action: "list", venue_id: venueId }),
    deps({
      apiKey: "chave-reserva",
      fetchFn: () => {
        called = true;
        return Promise.resolve(new Response(""));
      },
    }),
  );
  assertEquals(response.status, 403);
  assertEquals(called, false);
});

function png(): string {
  return btoa(String.fromCharCode(
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0,
    0,
  ));
}

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

function asaasDocuments(): VenueDocumentDeps["fetchFn"] {
  return (url) => {
    if (String(url).endsWith("/myAccount/status")) {
      return jsonResponse({
        documentation: "APPROVED",
        general: "APPROVED",
      });
    }
    return jsonResponse({
      data: [{
        id: "doc_sem_link_1",
        status: "APPROVED",
        type: "IDENTIFICATION",
        title: "RG",
      }],
    });
  };
}

function request(body: Record<string, unknown>, jwt = "token"): Request {
  return new Request("https://example.test/venue-documents", {
    method: "POST",
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
    body: JSON.stringify(body),
  });
}

function jsonResponse(body: unknown): Promise<Response> {
  return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
}

function deps(input: {
  fetchFn: VenueDocumentDeps["fetchFn"];
  role?: DocumentAccess | VenueDocumentDeps["role"];
  actorId?: string;
  strong?: boolean;
  base?: string;
  apiKey?: string;
}): VenueDocumentDeps {
  const apiKey = input.apiKey ?? secret;
  const role = input.role ?? "owner";
  return {
    env: {
      get: (name) => {
        if (name === "ASAAS_BASE_URL") return input.base ?? asaasSandboxBaseUrl;
        if (name === "ASAAS_POINTS_RESERVE_API_KEY") return "chave-reserva";
        return "";
      },
    },
    fetchFn: input.fetchFn,
    actor: () =>
      Promise.resolve(
        input.actorId === "" ? null : { id: input.actorId ?? "user-1" },
      ),
    role: typeof role === "function" ? role : () => Promise.resolve(role),
    subaccount: () => Promise.resolve({ apiKey, walletId: "wal_casa" }),
    strongAuth: () => Promise.resolve(input.strong ?? false),
  };
}
