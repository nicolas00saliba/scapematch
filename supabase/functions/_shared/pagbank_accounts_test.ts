import { assertEquals } from "jsr:@std/assert@1";
import {
  classifySignupProbe,
  handlePagbankSignup,
  handlePagbankSignupProbe,
  parseSignup,
  sellerAccountBody,
  signupProbeBody,
  type ProbeStore,
  type SignupDraft,
  type SignupStore,
} from "./pagbank_accounts.ts";
import type { EnvLike } from "./http.ts";

const venue = "d7444444-4444-4444-8444-444444444444";
const owner = "d7111111-1111-4111-8111-111111111111";
const today = new Date("2026-11-24T15:00:00.000Z");
const cpf = "52998224725";
const cnpj = "11222333000181";

function env(values: Record<string, string> = {}): EnvLike {
  return { get: (name) => values[name] };
}

function readyEnv(): EnvLike {
  return env({
    PAGBANK_ENV: "sandbox",
    PAGBANK_TOKEN: "token-pagbank-teste",
    PAGBANK_CONNECT_CLIENT_ID: "client-id-teste",
    PAGBANK_CONNECT_CLIENT_SECRET: "client-secret-teste",
    PAGBANK_SIGNUP_PROBE_SECRET: "segredo-da-sonda",
  });
}

function draft(kind: "cpf" | "cnpj" = "cpf"): SignupDraft {
  const parsed = parseSignup({
    venue_id: venue,
    document_kind: kind,
    document_number: kind === "cpf" ? cpf : cnpj,
    responsible_cpf: kind === "cnpj" ? cpf : "",
    company_name: kind === "cnpj" ? "Casa Escape Ltda" : "Casa Escape",
    street: "Rua das Salas",
    number: "10",
    complement: "",
    locality: "Centro",
    city: "Curitiba",
    region_code: "pr",
    postal_code: "80010-010",
    responsible_name: "Ana Souza",
    birth_date: "1991-10-10",
    phone: "(11) 98765-4321",
    email: "ana@casa.example",
    business_category: "ENTERTAINMENT",
    terms_accepted: true,
  }, today);
  if (typeof parsed === "string") throw new Error(parsed);
  return parsed;
}

Deno.test("a sonda só liga com 400 de validação inequívoco", () => {
  const ok = JSON.stringify({
    error_messages: [{
      code: "40001",
      description: "Parâmetro obrigatório",
      parameter_name: "email",
    }],
  });
  assertEquals(classifySignupProbe(400, ok).decision, "enabled");
  assertEquals(
    classifySignupProbe(400, JSON.stringify({
      error_messages: [
        { code: "40002", description: "inválido", parameter_name: "type" },
        { code: "40001", description: "obrigatório", parameter_name: "person" },
      ],
    })).code,
    "40002",
  );
  for (const status of [200, 201, 401, 403, 404, 500]) {
    assertEquals(classifySignupProbe(status, ok).decision, status < 300 ? "accident" : "closed");
  }
  assertEquals(
    classifySignupProbe(400, JSON.stringify({
      error_messages: [{ code: "40001", description: "obrigatório" }],
    })).code,
    "http_400_sem_campo",
  );
  assertEquals(
    classifySignupProbe(400, JSON.stringify({
      error_messages: [{
        code: "40001",
        description: "forbidden",
        parameter_name: "email",
      }],
    })).decision,
    "closed",
  );
  assertEquals(
    classifySignupProbe(201, JSON.stringify({ id: "ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36" })).decision,
    "accident",
  );
  assertEquals(signupProbeBody, { type: "SELLER" });
});

Deno.test("PF não manda empresa e PJ manda CNPJ e CPF do responsável", () => {
  const person = sellerAccountBody(draft("cpf"), "203.0.113.8", today);
  assertEquals(person.type, "SELLER");
  assertEquals(person.company, undefined);
  assertEquals((person.person as { tax_id: string }).tax_id, cpf);
  assertEquals(person.business_category, "ENTERTAINMENT");
  const company = sellerAccountBody(draft("cnpj"), "203.0.113.8", today);
  const firm = company.company as { tax_id: string; name: string };
  assertEquals(firm.tax_id, cnpj);
  assertEquals(firm.name, "Casa Escape Ltda");
  assertEquals((company.person as { tax_id: string }).tax_id, cpf);
  assertEquals((company.tos_acceptance as { user_ip: string }).user_ip, "203.0.113.8");
});

Deno.test("menor de idade e categoria fora do enum não passam", () => {
  const young = parseSignup({
    ...bodyOf("cpf"),
    birth_date: "2010-01-01",
  }, today);
  assertEquals(young, "nascimento");
  const category = parseSignup({
    ...bodyOf("cpf"),
    business_category: "ESCAPE_ROOM",
  }, today);
  assertEquals(category, "categoria");
  assertEquals(parseSignup({ ...bodyOf("cpf"), terms_accepted: false }, today), "termos");
});

Deno.test("modo A não chama a PagBank nem devolve o CPF", async () => {
  let called = false;
  const response = await handlePagbankSignup(request(bodyOf("cpf")), {
    env: readyEnv(),
    fetchFn: () => {
      called = true;
      return Promise.resolve(new Response(""));
    },
    now: () => today,
    store: store({ api: false }),
  });
  assertEquals(response.status, 409);
  assertEquals(await response.json(), { error: "api_indisponivel" });
  assertEquals(called, false);
});

Deno.test("modo B cria a conta e não ecoa o documento", async () => {
  const seen: { url?: string; body?: string; headers?: Headers } = {};
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    const response = await handlePagbankSignup(request(bodyOf("cnpj"), {
      "x-real-ip": "203.0.113.8",
    }), {
      env: readyEnv(),
      fetchFn: (_url, init) => {
        seen.url = String(_url);
        seen.body = String(init?.body ?? "");
        seen.headers = new Headers(init?.headers);
        return Promise.resolve(new Response(JSON.stringify({
          id: "ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36",
        }), { status: 201 }));
      },
      now: () => today,
      store: store({ api: true }),
    });
    assertEquals(response.status, 200);
    const payload = await response.json();
    assertEquals(payload.account_id, "ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36");
    assertEquals(JSON.stringify(payload).includes(cnpj), false);
    assertEquals(JSON.stringify(payload).includes(cpf), false);
    assertEquals(seen.url, "https://sandbox.api.pagseguro.com/accounts");
    assertEquals(seen.headers?.get("x-client-id"), "client-id-teste");
    assertEquals(seen.headers?.get("authorization"), "Bearer token-pagbank-teste");
    assertEquals(seen.body?.includes(cnpj), true);
    assertEquals(logs.join("\n").includes(cnpj), false);
    assertEquals(logs.join("\n").includes("client-secret-teste"), false);
  } finally {
    console.error = original;
  }
});

Deno.test("conta exists sem ACCO_ não chama POST de novo", async () => {
  let calls = 0;
  let prior: { accountId: string | null; status: string | null } | null = null;
  const saved: string[] = [];
  const stateful: SignupStore = {
    actor: () => Promise.resolve({ id: owner, admin: false }),
    venue: () => Promise.resolve({ id: venue, ownerId: owner, status: "approved" }),
    apiEnabled: () => Promise.resolve(true),
    existingSignup: () => Promise.resolve(prior),
    saveAccount: (input) => {
      saved.push(`${input.status}:${input.accountId ?? ""}`);
      prior = { accountId: input.accountId, status: input.status };
      return Promise.resolve();
    },
  };
  const fetchFn = () => {
    calls += 1;
    return Promise.resolve(new Response(JSON.stringify({
      error_messages: [{
        code: "42001",
        description: "conta já existe",
        parameter_name: "email",
      }],
    }), { status: 400 }));
  };
  const deps = {
    env: readyEnv(),
    fetchFn,
    now: () => today,
    store: stateful,
  };
  const first = await handlePagbankSignup(
    request(bodyOf("cpf"), { "x-real-ip": "203.0.113.8" }),
    deps,
  );
  assertEquals(first.status, 409);
  assertEquals(await first.json(), {
    error: "conta_existente",
    account_status: "exists",
  });
  const second = await handlePagbankSignup(
    request(bodyOf("cpf"), { "x-real-ip": "203.0.113.8" }),
    deps,
  );
  assertEquals(second.status, 409);
  assertEquals(await second.json(), {
    error: "conta_existente",
    account_status: "exists",
  });
  assertEquals(calls, 1);
  assertEquals(saved, ["exists:"]);
});

Deno.test("a sonda não liga em 401 e avisa só na transição", async () => {
  const alerts: string[] = [];
  const applied: boolean[] = [];
  const bodies: string[] = [];
  const closed = await handlePagbankSignupProbe(probeRequest(), {
    env: readyEnv(),
    fetchFn: (_url, init) => {
      bodies.push(String(init?.body ?? ""));
      return Promise.resolve(new Response("{}", { status: 401 }));
    },
    store: probeStore(applied, false),
    alert: (code) => {
      alerts.push(code);
      return Promise.resolve();
    },
  });
  assertEquals(closed.status, 200);
  assertEquals((await closed.json()).enabled, false);
  assertEquals(alerts, []);
  assertEquals(bodies, ['{"type":"SELLER"}']);
  assertEquals(applied, [false]);

  const opened = await handlePagbankSignupProbe(probeRequest(), {
    env: readyEnv(),
    fetchFn: () =>
      Promise.resolve(new Response(JSON.stringify({
        error_messages: [{
          code: "40001",
          description: "Parâmetro obrigatório",
          parameter_name: "email",
        }],
      }), { status: 400 })),
    store: probeStore(applied, true),
    alert: (code) => {
      alerts.push(code);
      return Promise.resolve();
    },
  });
  assertEquals((await opened.json()).changed, true);
  assertEquals(alerts, ["api_liberada"]);

  const accident = await handlePagbankSignupProbe(probeRequest(), {
    env: readyEnv(),
    fetchFn: () => Promise.resolve(new Response("{}", { status: 201 })),
    store: probeStore(applied, false),
    alert: (code) => {
      alerts.push(code);
      return Promise.resolve();
    },
  });
  assertEquals((await accident.json()).enabled, false);
  assertEquals(alerts.at(-1), "probe_criou_conta");
});

Deno.test("sonda sem segredo não chama a PagBank", async () => {
  let called = false;
  const response = await handlePagbankSignupProbe(
    new Request("https://example.test/", { method: "POST" }),
    {
      env: readyEnv(),
      fetchFn: () => {
        called = true;
        return Promise.resolve(new Response(""));
      },
      store: probeStore([], false),
      alert: () => Promise.resolve(),
    },
  );
  assertEquals(response.status, 401);
  assertEquals(called, false);
});

function bodyOf(kind: "cpf" | "cnpj"): Record<string, unknown> {
  return {
    venue_id: venue,
    document_kind: kind,
    document_number: kind === "cpf" ? cpf : cnpj,
    responsible_cpf: kind === "cnpj" ? cpf : "",
    company_name: kind === "cnpj" ? "Casa Escape Ltda" : "Casa Escape",
    street: "Rua das Salas",
    number: "10",
    complement: "",
    locality: "Centro",
    city: "Curitiba",
    region_code: "PR",
    postal_code: "80010010",
    responsible_name: "Ana Souza",
    birth_date: "1991-10-10",
    phone: "11987654321",
    email: "ana@casa.example",
    business_category: "ENTERTAINMENT",
    terms_accepted: true,
  };
}

function request(body: unknown, extra: Record<string, string> = {}): Request {
  return new Request("https://parceiro.escapematch.com.br/signup", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer jwt",
      ...extra,
    },
    body: JSON.stringify(body),
  });
}

function probeRequest(): Request {
  return new Request("https://example.test/probe", {
    method: "POST",
    headers: { "x-pagbank-signup-probe-secret": "segredo-da-sonda" },
  });
}

function store(input: { api: boolean }): SignupStore {
  return {
    actor: () => Promise.resolve({ id: owner, admin: false }),
    venue: () => Promise.resolve({ id: venue, ownerId: owner, status: "approved" }),
    apiEnabled: () => Promise.resolve(input.api),
    existingSignup: () => Promise.resolve(null),
    saveAccount: () => Promise.resolve(),
  };
}

function probeStore(applied: boolean[], changed: boolean): ProbeStore {
  return {
    apply: (input) => {
      applied.push(input.enable);
      return Promise.resolve({ enabled: input.enable && changed, changed });
    },
  };
}
