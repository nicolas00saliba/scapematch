import { assert, assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider } from "./pagbank_provider.ts";
import {
  cardReregisterCode,
  chargeAsksNewCard,
  customerWithCpf,
  playerCpfDigits,
  resolveCustomerWithCpf,
  storeReplacedCustomer,
} from "./player_cpf.ts";

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
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    fetchFn,
  );
  try {
    const created = await customerWithCpf(pagbank, {
      customerId: null,
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf: "529.982.247-25",
    });
    assertEquals(created, "PB_CUS_user-1");
    assertEquals(calls.length, 0);

    const updated = await customerWithCpf(pagbank, {
      customerId: "cus_empty",
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf,
    });
    assertEquals(updated, "PB_CUS_user-1");
    assertEquals(calls.length, 0);

    const kept = await customerWithCpf(pagbank, {
      customerId: "PB_CUS_user-1",
      name: "Ana",
      email: "ana@example.com",
      externalReference: "user-1",
      cpf,
    });
    assertEquals(kept, "PB_CUS_user-1");
    assertEquals(calls.length, 0);
  } finally {
    console.error = original;
  }
  const joined = logs.join("\n") + calls.map((call) => call.body).join("\n");
  assertEquals(joined.includes("pagbank-secret-key"), false);
  assert(logs.length === 0);
});

Deno.test("resposta do PagBank não deixa o cpf no erro", async () => {
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
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
  const error = await pagbank.tokenizeCard({
    customer: "PB_CUS_user-1",
    creditCard: {
      holderName: "ANA",
      number: "4111111111111111",
      expiryMonth: "12",
      expiryYear: "2030",
      ccv: "123",
    },
    creditCardHolderInfo: {
      name: "Ana",
      email: "ana@example.com",
      cpfCnpj: cpf,
      postalCode: "80000000",
      addressNumber: "1",
      phone: "41999999999",
    },
  }).catch((caught: unknown) => caught);
  const message = error instanceof Error ? error.message : String(error);
  assertEquals(message.includes(cpf), false);
  assert(message.startsWith("PagBank 400"));
});

Deno.test("customer 404 ou deleted é recriado e o cartão antigo pede recadastro", async () => {
  const calls: { url: string; method: string }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method ?? "GET" });
    if (url.endsWith("/customers/cus_404")) {
      return Promise.resolve(
        new Response(JSON.stringify({ errors: [{ code: "not_found" }] }), {
          status: 404,
        }),
      );
    }
    if (url.endsWith("/customers/cus_gone") && (init?.method ?? "GET") === "GET") {
      return Promise.resolve(
        json({ id: "cus_gone", cpfCnpj: cpf, deleted: true }),
      );
    }
    if (url.endsWith("/customers") && init?.method === "POST") {
      const id = calls.some((call) => call.url.endsWith("/customers/cus_404"))
        ? "cus_404_novo"
        : "cus_gone_novo";
      return Promise.resolve(json({ id }));
    }
    return Promise.resolve(new Response("no", { status: 500 }));
  };
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    fetchFn,
  );
  const input = {
    name: "Ana",
    email: "ana@example.com",
    externalReference: "user-1",
    cpf,
  };
  const missing = await resolveCustomerWithCpf(pagbank, {
    ...input,
    customerId: "cus_404",
  });
  assertEquals(missing, { id: "PB_CUS_user-1", replacedId: "cus_404" });
  assertEquals(calls.length, 0);

  calls.length = 0;
  const deleted = await resolveCustomerWithCpf(pagbank, {
    ...input,
    customerId: "cus_gone",
  });
  assertEquals(deleted, { id: "PB_CUS_user-1", replacedId: "cus_gone" });
  assertEquals(calls.length, 0);
  assertEquals(
    calls.some((call) => call.method === "PUT"),
    false,
  );

  const order: string[] = [];
  const replaced = await storeReplacedCustomer(
    {
      rpc(name) {
        order.push(name);
        return Promise.resolve({ data: 1, error: null });
      },
      from() {
        return {
          update() {
            const chain = {
              eq() {
                return chain;
              },
              is() {
                return chain;
              },
              select() {
                order.push("profile");
                return Promise.resolve({
                  data: [{ pagbank_customer_id: "cus_404_novo" }],
                  error: null,
                });
              },
              maybeSingle() {
                return Promise.resolve({ data: null, error: null });
              },
            };
            return chain;
          },
          select() {
            return {
              eq() {
                return {
                  maybeSingle() {
                    return Promise.resolve({ data: null, error: null });
                  },
                };
              },
              is() {
                return this;
              },
              select() {
                return Promise.resolve({ data: [], error: null });
              },
              maybeSingle() {
                return Promise.resolve({ data: null, error: null });
              },
            };
          },
        };
      },
    },
    "user-1",
    "cus_404",
    "cus_404_novo",
  );
  assertEquals(replaced, { id: "cus_404_novo", replacedId: "cus_404" });
  assertEquals(order, ["deactivate_customer_saved_cards", "profile"]);
  assertEquals(chargeAsksNewCard(replaced.replacedId, "card-1"), true);
  assertEquals(chargeAsksNewCard(replaced.replacedId, ""), false);
  assertEquals(chargeAsksNewCard(null, "card-1"), false);
  assertEquals(cardReregisterCode, "card_reregister");
});

Deno.test("duas trocas simultâneas ficam com um customer e apagam o perdedor", async () => {
  let profile = "cus_old";
  const deleted: string[] = [];
  const db = {
    rpc() {
      return Promise.resolve({ data: 1, error: null });
    },
    from() {
      return {
        update(values: Record<string, unknown>) {
          const next = String(values.pagbank_customer_id);
          const filters: Record<string, string> = {};
          const chain = {
            eq(column: string, value: string) {
              filters[column] = value;
              return chain;
            },
            is() {
              return chain;
            },
            select() {
              const previous = filters.pagbank_customer_id;
              if (profile === previous) {
                profile = next;
                return Promise.resolve({
                  data: [{ pagbank_customer_id: next }],
                  error: null,
                });
              }
              return Promise.resolve({ data: [], error: null });
            },
            maybeSingle() {
              return Promise.resolve({ data: null, error: null });
            },
          };
          return chain;
        },
        select() {
          return {
            eq() {
              return {
                maybeSingle() {
                  return Promise.resolve({
                    data: { pagbank_customer_id: profile },
                    error: null,
                  });
                },
              };
            },
            is() {
              return this;
            },
            select() {
              return Promise.resolve({ data: [], error: null });
            },
            maybeSingle() {
              return Promise.resolve({
                data: { pagbank_customer_id: profile },
                error: null,
              });
            },
          };
        },
      };
    },
  };
  const pagbank = {
    deleteCustomer(id: string) {
      deleted.push(id);
      return Promise.reject(new Error("PagBank 400: sem apagar"));
    },
  };
  const [first, second] = await Promise.all([
    storeReplacedCustomer(db, "user-1", "cus_old", "cus_a", pagbank),
    storeReplacedCustomer(db, "user-1", "cus_old", "cus_b", pagbank),
  ]);
  assertEquals(first.id, second.id);
  assertEquals(first.replacedId, "cus_old");
  assertEquals(second.replacedId, "cus_old");
  assertEquals(profile, first.id);
  assertEquals(deleted, [first.id === "cus_a" ? "cus_b" : "cus_a"]);
  assertEquals(chargeAsksNewCard(second.replacedId, "card-1"), true);

  deleted.length = 0;
  profile = "cus_old";
  const loserDeletes = {
    deleteCustomer(id: string) {
      deleted.push(id);
      return Promise.resolve();
    },
  };
  const winner = await storeReplacedCustomer(
    db,
    "user-1",
    "cus_old",
    "cus_win",
    loserDeletes,
  );
  const loser = await storeReplacedCustomer(
    db,
    "user-1",
    "cus_old",
    "cus_lose",
    loserDeletes,
  );
  assertEquals(winner.id, "cus_win");
  assertEquals(loser.id, "cus_win");
  assertEquals(deleted, ["cus_lose"]);
  assertEquals(profile, "cus_win");
});

Deno.test("customer 500 não recria e não troca o id", async () => {
  let posts = 0;
  const pagbank = new PagBankProvider(
    "pagbank-secret-key",
    "https://sandbox.api.pagseguro.com",
    (url, init) => {
      if (init?.method === "POST") posts += 1;
      return Promise.resolve(new Response("no", { status: 500 }));
    },
  );
  const kept = await resolveCustomerWithCpf(pagbank, {
    customerId: "PB_CUS_user-1",
    name: "Ana",
    email: "ana@example.com",
    externalReference: "user-1",
    cpf,
  });
  assertEquals(kept.id, "PB_CUS_user-1");
  assertEquals(kept.replacedId, null);
  assertEquals(posts, 0);
});

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
