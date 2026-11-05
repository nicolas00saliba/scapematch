import { assert, assertEquals } from "jsr:@std/assert@1";
import { AsaasProvider } from "./asaas_provider.ts";
import { customerWithCpf, playerCpfDigits } from "./player_cpf.ts";

const cpf = "52998224725";

Deno.test("cpf do jogador só aceita os 11 dígitos verificados", () => {
  assertEquals(playerCpfDigits("529.982.247-25"), cpf);
  assertEquals(playerCpfDigits(cpf), cpf);
  assertEquals(playerCpfDigits("111.111.111-11"), null);
  assertEquals(playerCpfDigits("52998224724"), null);
  assertEquals(playerCpfDigits("123"), null);
  assertEquals(playerCpfDigits(null), null);
});

Deno.test("customer novo nasce com cpf e o antigo sem cpf é atualizado", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const calls: { url: string; method: string; body: string }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({
      url,
      method: init?.method ?? "GET",
      body: typeof init?.body === "string" ? init.body : "",
    });
    if (url.endsWith("/customers") && init?.method === "POST") {
      return Promise.resolve(json({ id: "cus_new" }));
    }
    if (url.endsWith("/customers/cus_empty") && (init?.method ?? "GET") === "GET") {
      return Promise.resolve(json({ id: "cus_empty", cpfCnpj: "" }));
    }
    if (url.endsWith("/customers/cus_empty") && init?.method === "PUT") {
      return Promise.resolve(json({ id: "cus_empty" }));
    }
    if (url.endsWith("/customers/cus_ok")) {
      return Promise.resolve(json({ id: "cus_ok", cpfCnpj: "390.533.447-05" }));
    }
    return Promise.resolve(new Response("no", { status: 500 }));
  };
  const asaas = new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  try {
    const created = await customerWithCpf(asaas, {
      customerId: null,
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf: "529.982.247-25",
    });
    assertEquals(created, "cus_new");
    const posted = JSON.parse(calls[0].body);
    assertEquals(posted.cpfCnpj, cpf);
    assertEquals(calls[0].method, "POST");

    calls.length = 0;
    const updated = await customerWithCpf(asaas, {
      customerId: "cus_empty",
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf,
    });
    assertEquals(updated, "cus_empty");
    assertEquals(calls.map((call) => call.method), ["GET", "PUT"]);
    assertEquals(JSON.parse(calls[1].body), { cpfCnpj: cpf });

    calls.length = 0;
    const kept = await customerWithCpf(asaas, {
      customerId: "cus_ok",
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf,
    });
    assertEquals(kept, "cus_ok");
    assertEquals(calls.map((call) => call.method), ["GET"]);
  } finally {
    console.error = original;
  }
  const joined = logs.join("\n") + calls.map((call) => call.body).join("\n");
  assertEquals(joined.includes("asaas-secret-key"), false);
  assert(logs.length === 0);
});

Deno.test("resposta do Asaas não deixa o cpf no erro", async () => {
  const asaas = new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            cpfCnpj: cpf,
            errors: [{ description: `cpfCnpj: ${cpf}` }],
          }),
          { status: 400 },
        ),
      ),
  );
  const error = await asaas.createCustomer({
    name: "Ana",
    email: "ana@example.com",
    externalReference: "user-1",
    cpfCnpj: cpf,
  }).catch((caught: unknown) => caught);
  const message = error instanceof Error ? error.message : String(error);
  assertEquals(message.includes(cpf), false);
  assert(message.startsWith("Asaas 400"));
});

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
