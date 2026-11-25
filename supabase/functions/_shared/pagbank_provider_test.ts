import {
  assert,
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1";
import {
  PagBankProvider,
  pagbankOrderNotificationUrl,
  pagbankProductionBaseUrl,
  pagbankSandboxBaseUrl,
  pagbankSignatureMatches,
} from "./pagbank_provider.ts";
import { groupPaymentAction } from "./pagbank_rules.ts";

const venue = "ACCO_VENUE";
const primary = "ACCO_PRIMARY";

function provider(
  fetchFn: (url: string, init?: RequestInit) => Promise<Response>,
) {
  return new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    fetchFn,
    () => Promise.resolve(),
    primary,
  );
}

Deno.test("produção é o padrão e sandbox só com a env", () => {
  const live = PagBankProvider.fromEnv({
    get: (name) => name === "PAGBANK_TOKEN" ? "tok" : undefined,
  });
  assertEquals(live.sandbox, false);
  assertEquals(live.official, true);
  const forced = PagBankProvider.fromEnv({
    get: (name) => {
      if (name === "PAGBANK_TOKEN") return "tok";
      if (name === "PAGBANK_ENV") return "sandbox";
      if (name === "PAGBANK_ACCOUNT_ID") return primary;
      return undefined;
    },
  });
  assertEquals(forced.sandbox, true);
  const ignored = PagBankProvider.fromEnv({
    get: (name) => {
      if (name === "PAGBANK_TOKEN") return "tok";
      if (name === "PAGBANK_BASE_URL") return pagbankSandboxBaseUrl;
      return undefined;
    },
  });
  assertEquals(ignored.sandbox, false);
  assertEquals(pagbankSandboxBaseUrl.includes("sandbox"), true);
  assertEquals(pagbankProductionBaseUrl, "https://api.pagseguro.com");
});

Deno.test("Pix FIXED: a casa leva o bruto, a taxa fica na primária e a custódia liga", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    if ((init?.method ?? "GET") === "GET") {
      return Promise.resolve(
        new Response(JSON.stringify({ orders: [] }), { status: 200 }),
      );
    }
    return Promise.resolve(
      new Response(JSON.stringify({
        id: "ORDE_1",
        charges: [{
          id: "CHAR_1",
          status: "WAITING",
          reference_id: "charge-1",
          splits: { id: "SPLI_1" },
          payment_method: {
            type: "PIX",
            pix: { qr_code: { text: "000201PIX", image: "aW1n" } },
          },
        }],
      }), { status: 200 }),
    );
  };
  const pix = await provider(fetchFn).createPix({
    customer: "PB_CUS_1",
    value: 100,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "charge-1",
    split: { walletId: venue, fixedValue: 75 },
    customerDetails: {
      name: "Jogador",
      email: "jogador@example.com",
      taxId: "52998224725",
    },
  });
  assertEquals(pix.id, "ORDE_1");
  assertEquals(pix.payload, "000201PIX");
  assertEquals(pix.splitId, "SPLI_1");
  assertEquals(pix.status, "PENDING");
  const post = calls.find((call) => call.init.method === "POST");
  assert(post);
  assert(post.url.endsWith("/orders"));
  const body = JSON.parse(String(post.init.body));
  const charge = body.charges[0];
  assertEquals(charge.payment_method.type, "PIX");
  assertEquals(
    charge.payment_method.pix.expiration_date,
    "2026-11-07T23:59:00-03:00",
  );
  assertEquals(charge.payment_method.capture, undefined);
  assertEquals(body.qr_codes, undefined);
  assertEquals(charge.splits.method, "FIXED");
  assertEquals(charge.splits.receivers[0].amount.value, 7500);
  assertEquals(charge.splits.receivers[0].account.id, venue);
  assertEquals(charge.splits.receivers[0].configurations.custody.apply, true);
  assertEquals(charge.splits.receivers[1].amount.value, 2500);
  assertEquals(charge.splits.receivers[1].account.id, primary);
  assertEquals(JSON.stringify(body).includes("pb-token-secret"), false);
  const headers = post.init.headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer pb-token-secret");
});

Deno.test("todo pedido manda a URL de notificação do webhook", async () => {
  const notice = "https://example.supabase.co/functions/v1/pagbank-webhook";
  const posted: Record<string, unknown>[] = [];
  const order = {
    charges: [{
      id: "CHAR_PIX",
      status: "WAITING",
      splits: { id: "SPLI_1" },
      payment_method: {
        type: "PIX",
        pix: { qr_code: { text: "000201PIX", image: "aW1n" } },
      },
    }],
  };
  const fetchFn = (_url: string, init?: RequestInit) => {
    if ((init?.method ?? "GET") === "POST") {
      posted.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(JSON.stringify(order), { status: 200 }),
      );
    }
    return Promise.resolve(
      new Response(JSON.stringify({ orders: [] }), { status: 200 }),
    );
  };
  const client = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    fetchFn,
    () => Promise.resolve(),
    primary,
    notice,
  );
  await client.createPix({
    customer: "PB_CUS_1",
    value: 50,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "pix-notice",
    split: { walletId: venue, fixedValue: 40 },
  });
  await client.authorizeCard({
    customer: "PB_CUS_1",
    value: 50,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "card-notice",
    split: { walletId: venue, fixedValue: 40 },
    creditCardToken: "CARD_1",
  });
  assertEquals(posted.length, 2);
  assertEquals(posted[0].notification_urls, [notice]);
  assertEquals(posted[1].notification_urls, [notice]);
  assertEquals(
    pagbankOrderNotificationUrl({
      get: (name) =>
        name === "SUPABASE_URL" ? "https://example.supabase.co/" : undefined,
    }),
    notice,
  );
});

Deno.test("cartão até 3x não manda juro e nasce sem captura", async () => {
  let posted: Record<string, unknown> = {};
  const fetchFn = (url: string, init?: RequestInit) => {
    if ((init?.method ?? "GET") === "POST" && url.endsWith("/orders")) {
      posted = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        charges: [{
          id: "CHAR_CARD",
          status: "AUTHORIZED",
          splits: { id: "SPLI_CARD" },
        }],
      }), { status: 200 }));
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  const card = await provider(fetchFn).authorizeCard({
    customer: "PB_CUS_1",
    value: 200,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "card-1",
    split: { walletId: venue, fixedValue: 150 },
    creditCardToken: "CARD_1",
    installments: 3,
    buyerInterestCents: 999,
  });
  assertEquals(card.status, "AUTHORIZED");
  const charge = (posted.charges as Record<string, unknown>[])[0];
  const method = charge.payment_method as { capture: boolean; installments: number };
  assertEquals(method.capture, false);
  assertEquals(method.installments, 3);
  assertEquals((charge.amount as { fees?: unknown }).fees, undefined);
  assertEquals((charge.amount as { value: number }).value, 20000);
});

Deno.test("4x é recusado antes de cotar juro ou autorizar", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  await assertRejects(
    () =>
      provider(fetchFn).authorizeCard({
        customer: "PB_CUS_1",
        value: 200,
        dueDate: "2026-11-07",
        description: "EscapeMatch",
        externalReference: "card-4",
        split: { walletId: venue, fixedValue: 150 },
        creditCardToken: "CARD_1",
        installments: 4,
      }),
    Error,
    "parcelas",
  );
  assertEquals(calls, []);
});

Deno.test("captura, estorno e custódia usam os caminhos da PagBank", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
    if ((init?.method ?? "GET") === "GET") {
      return Promise.resolve(new Response(JSON.stringify({
        id: "CHAR_1",
        status: "AUTHORIZED",
        amount: { value: 10000, currency: "BRL" },
      }), { status: 200 }));
    }
    if (url.endsWith("/capture") || url.endsWith("/cancel")) {
      const posted = JSON.parse(String(init?.body));
      assertEquals(posted.amount.value, 10000);
    }
    if (url.endsWith("/capture")) {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "CHAR_1", status: "PAID" }), {
          status: 200,
        }),
      );
    }
    if (url.endsWith("/cancel")) {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "CHAR_1", status: "CANCELED" }), {
          status: 200,
        }),
      );
    }
    if (url.endsWith("/custody/release")) {
      const posted = JSON.parse(String(init?.body));
      assertEquals(posted.receivers, [
        { account: { id: venue } },
        { account: { id: primary } },
      ]);
      return Promise.resolve(new Response("", { status: 200 }));
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  const client = provider(fetchFn);
  const captured = await client.capture("CHAR_1");
  assertEquals(captured.status, "CONFIRMED");
  const refunded = await client.refund("CHAR_1");
  assertEquals(refunded.status, "REFUNDED");
  const voided = await client.cancelAuthorization("CHAR_1");
  assertEquals(voided.status, "CANCELED");
  await client.releaseCustody("SPLI_1", [venue, primary]);
  assert(calls.some((call) => call.includes("/charges/CHAR_1/capture")));
  assert(calls.some((call) => call.includes("/charges/CHAR_1/cancel")));
  assert(calls.some((call) =>
    call.endsWith("/splits/SPLI_1/custody/release")
  ));
  const release = calls.find((call) => call.includes("custody/release"));
  assert(release);
  let posted = 0;
  await assertRejects(
    () =>
      provider(() => {
        posted += 1;
        return Promise.resolve(new Response("", { status: 200 }));
      }).releaseCustody("SPLI_1", []),
    Error,
    "custodia_recebedores",
  );
  assertEquals(posted, 0);
});

Deno.test("a assinatura do webhook usa o corpo cru", async () => {
  const secret = "webhook-secret-pagbank-32";
  const raw = '{"id":"CHAR_1","status":"PAID"}';
  const good = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${secret}-${raw}`),
  );
  const hex = [...new Uint8Array(good)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  assertEquals(await pagbankSignatureMatches(hex, secret, raw), true);
  assertEquals(await pagbankSignatureMatches(hex, secret, `${raw} `), false);
  assertEquals(await pagbankSignatureMatches(null, secret, raw), false);
});

Deno.test("parcela abaixo de R$ 5 não vai para a PagBank e a casa não perde a taxa", async () => {
  let posted = 0;
  const fetchFn = () => {
    posted += 1;
    return Promise.resolve(new Response("{}", { status: 500 }));
  };
  await assertRejects(
    () =>
      provider(fetchFn).authorizeCard({
        customer: "PB_CUS_1",
        value: 9,
        dueDate: "2026-11-07",
        description: "EscapeMatch",
        externalReference: "card-baixo",
        split: { walletId: venue, fixedValue: 7 },
        creditCardToken: "CARD_1",
        installments: 2,
      }),
    Error,
    "parcelas",
  );
  assertEquals(posted, 0);

  const calls: Record<string, unknown>[] = [];
  const pix = await provider((url, init) => {
    if ((init?.method ?? "GET") === "POST") {
      calls.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify({
        charges: [{
          id: "CHAR_P",
          status: "WAITING",
          splits: { id: "SPLI_P" },
          payment_method: { type: "PIX", pix: { qr_code: { text: "000201PIX" } } },
        }],
      }), { status: 200 }));
    }
    return Promise.resolve(new Response(JSON.stringify({ orders: [] }), { status: 200 }));
  }).createPix({
    customer: "PB_CUS_1",
    value: 15,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "pix-15",
    split: { walletId: venue, fixedValue: 13.5 },
  });
  assertEquals(pix.splitId, "SPLI_P");
  const charge = (calls[0].charges as Record<string, unknown>[])[0];
  const receivers = ((charge.splits as { receivers: Record<string, unknown>[] }).receivers);
  assertEquals((receivers[0].amount as { value: number }).value, 1350);
  assertEquals((receivers[1].amount as { value: number }).value, 150);
  assertEquals(JSON.stringify(receivers[0]).includes("fee"), false);
});

Deno.test("confirmação solta a custódia; sem confirmação estorna o Pix e cancela o cartão", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
    if (url.endsWith("/custody/release")) {
      const posted = JSON.parse(String(init?.body));
      assertEquals(posted.receivers, [
        { account: { id: venue } },
        { account: { id: primary } },
      ]);
      return Promise.resolve(new Response("", { status: 200 }));
    }
    if ((init?.method ?? "GET") === "GET") {
      const parsed = new URL(url);
      const id = parsed.searchParams.get("charge_id") ??
        parsed.pathname.split("/").filter(Boolean).pop() ??
        "CHAR_1";
      return Promise.resolve(new Response(JSON.stringify({
        id,
        status: "PAID",
        amount: { value: 1500, currency: "BRL" },
      }), { status: 200 }));
    }
    if (url.includes("/cancel")) {
      const posted = JSON.parse(String(init?.body ?? "{}"));
      assertEquals(posted.amount.value, 1500);
    }
    return Promise.resolve(new Response(JSON.stringify({
      id: "CHAR_1",
      status: url.includes("cancel") ? "CANCELED" : "PAID",
    }), { status: 200 }));
  };
  const client = provider(fetchFn);
  const confirm = groupPaymentAction({
    confirmed: true,
    billingType: "PIX",
    status: "paid",
  });
  assertEquals(confirm, "release_custody");
  if (confirm === "release_custody") {
    await client.releaseCustody("SPLI_OK", [venue, primary]);
  }
  const pix = groupPaymentAction({
    confirmed: false,
    billingType: "PIX",
    status: "paid",
  });
  assertEquals(pix, "refund_pix");
  if (pix === "refund_pix") await client.refund("CHAR_PIX");
  const card = groupPaymentAction({
    confirmed: false,
    billingType: "CREDIT_CARD",
    status: "authorized",
  });
  assertEquals(card, "void_card");
  if (card === "void_card") await client.cancelAuthorization("CHAR_CARD");
  assert(calls.some((call) => call.endsWith("/splits/SPLI_OK/custody/release")));
  assert(calls.some((call) => call.endsWith("/charges/CHAR_PIX/cancel")));
  assert(calls.some((call) => call.endsWith("/charges/CHAR_CARD/cancel")));
  assertEquals(calls.some((call) => call.includes("/capture")), false);
});

Deno.test("erro da tokenização não ecoa o cartão", async () => {
  const fetchFn = (_url: string, init?: RequestInit) => {
    const echoed = String(init?.body ?? "");
    return Promise.resolve(
      new Response(echoed, { status: 400 }),
    );
  };
  const error = await assertRejects(() =>
    provider(fetchFn).tokenizeCard({
      customer: "PB_CUS_1",
      creditCard: {
        holderName: "JOGADOR",
        number: "4111111111111111",
        expiryMonth: "12",
        expiryYear: "2030",
        ccv: "123",
      },
      creditCardHolderInfo: {
        name: "JOGADOR",
        email: "jogador@example.com",
        cpfCnpj: "52998224725",
        postalCode: "80010000",
        addressNumber: "10",
        phone: "41999999999",
      },
    })
  );
  const message = error instanceof Error ? error.message : "";
  assertEquals(message.includes("4111111111111111"), false);
  assertEquals(message.includes("123"), false);
});

Deno.test("Connect troca o code e renova o refresh token", async () => {
  const bodies: Record<string, unknown>[] = [];
  const headers: Record<string, string>[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    assertEquals(url, `${pagbankProductionBaseUrl}/oauth2/token`);
    bodies.push(JSON.parse(String(init?.body ?? "{}")));
    headers.push({
      id: new Headers(init?.headers).get("X_CLIENT_ID") ?? "",
      secret: new Headers(init?.headers).get("X_CLIENT_SECRET") ?? "",
    });
    const grant = bodies.at(-1)?.grant_type;
    return Promise.resolve(Response.json({
      access_token: grant === "refresh_token" ? "access-novo" : "access-1",
      refresh_token: grant === "refresh_token" ? "refresh-novo" : "refresh-1",
      expires_in: 3600,
      account_id: "ACCO_CASA",
    }));
  };
  const client = provider(fetchFn);
  const exchanged = await client.exchangeConnectCode({
    clientId: "client-id",
    clientSecret: "client-secret",
    code: "code-1",
    redirectUri: "https://parceiro.escapematch.com.br/pagbank/retorno",
  });
  assertEquals(exchanged.accessToken, "access-1");
  assertEquals(exchanged.refreshToken, "refresh-1");
  assertEquals(exchanged.expiresIn, 3600);
  assertEquals(exchanged.accountId, "ACCO_CASA");
  assertEquals(bodies[0].grant_type, "authorization_code");
  assertEquals(bodies[0].code, "code-1");
  assertEquals(
    bodies[0].redirect_uri,
    "https://parceiro.escapematch.com.br/pagbank/retorno",
  );
  const refreshed = await client.refreshConnectToken({
    clientId: "client-id",
    clientSecret: "client-secret",
    refreshToken: "refresh-1",
  });
  assertEquals(refreshed.accessToken, "access-novo");
  assertEquals(refreshed.refreshToken, "refresh-novo");
  assertEquals(bodies[1].grant_type, "refresh_token");
  assertEquals(bodies[1].refresh_token, "refresh-1");
  assertEquals(headers[0].id, "client-id");
  assertEquals(headers[1].secret, "client-secret");
});

const pixCopy =
  "00020101021226880014br.gov.bcb.pix2566pix.example/qr/v2/escapematch";

function pixOrder(status: string) {
  return {
    id: "ORDE_PIX",
    reference_id: "charge-1",
    customer: { name: "Jogador", tax_id: "52998224725" },
    charges: [{
      id: "CHAR_PIX",
      reference_id: "charge-1",
      status,
      amount: { value: 10000, currency: "BRL" },
      payment_method: {
        type: "PIX",
        pix: { expiration_date: "2026-11-07T23:59:00-03:00" },
      },
      qr_code: { id: "QRCO_1", text: pixCopy },
      splits: {
        id: status === "PAID" ? "SPLI_PAGO" : "SPLI_CRIADO",
        method: "FIXED",
        receivers: [
          {
            account: { id: venue },
            amount: { value: 7500 },
            configurations: { custody: { apply: true } },
          },
        ],
      },
    }],
  };
}

Deno.test("consulta do Pix usa o pedido, antes e depois do pagamento", async () => {
  let paid = false;
  const fetchFn = (url: string, init?: RequestInit) => {
    assertEquals(init?.method ?? "GET", "GET");
    assert(url.endsWith("/orders/ORDE_PIX"));
    return Promise.resolve(
      new Response(JSON.stringify(pixOrder(paid ? "PAID" : "WAITING")), {
        status: 200,
      }),
    );
  };
  const client = provider(fetchFn);
  const waiting = await client.getPayment("ORDE_PIX");
  assertEquals(waiting.id, "ORDE_PIX");
  assertEquals(waiting.status, "PENDING");
  assertEquals(waiting.billingType, "PIX");
  assertEquals(waiting.expiresAt, "2026-11-07T23:59:00-03:00");
  assertEquals(waiting.splitId, "SPLI_CRIADO");
  paid = true;
  const done = await client.getPayment("ORDE_PIX");
  assertEquals(done.id, "ORDE_PIX");
  assertEquals(done.status, "CONFIRMED");
  assertEquals(done.splitId, "SPLI_PAGO");
});

Deno.test("criação do Pix devolve o pedido e o copia-e-cola do charge", async () => {
  const fetchFn = (url: string, init?: RequestInit) => {
    if ((init?.method ?? "GET") === "GET") {
      return Promise.resolve(
        new Response(JSON.stringify({ orders: [] }), { status: 200 }),
      );
    }
    assert(url.endsWith("/orders"));
    return Promise.resolve(
      new Response(JSON.stringify(pixOrder("WAITING")), { status: 200 }),
    );
  };
  const pix = await provider(fetchFn).createPix({
    customer: "PB_CUS_1",
    value: 100,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "charge-1",
    split: { walletId: venue, fixedValue: 75 },
  });
  assertEquals(pix.id, "ORDE_PIX");
  assertEquals(pix.payload, pixCopy);
  assertEquals(pix.splitId, "SPLI_CRIADO");
  assertEquals(pix.status, "PENDING");
});

Deno.test("a cotação de parcelas sai de uma consulta só", async () => {
  let quotes = 0;
  const fetchFn = (url: string) => {
    if (url.includes("/charges/fees/calculate")) {
      quotes += 1;
      return Promise.resolve(new Response(JSON.stringify({
        payment_methods: {
          credit_card: {
            visa: {
              installment_plans: [{
                installments: 4,
                interest_free: false,
                amount: {
                  value: 20640,
                  fees: { buyer: { interest: { total: 640 } } },
                },
              }],
            },
          },
        },
      }), { status: 200 }));
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  const client = provider(fetchFn);
  const plans = await client.quoteCardPlans(20_000);
  assertEquals(quotes, 1);
  assertEquals(plans.length, 3);
  assertEquals(plans[0].enabled, true);
  assertEquals(plans[2].amountCents, 20_000);
  assertEquals(plans[2].merchantAbsorbsInterest, true);
  assertEquals(plans.every((item) => item.merchantAbsorbsInterest), true);
  const small = await client.quoteCardPlans(10_000);
  assertEquals(quotes, 2);
  assertEquals(
    small.filter((item) => item.enabled).map((item) => item.installments),
    [1, 2, 3],
  );
  assertEquals(small[1].merchantAbsorbsInterest, true);
  await assertRejects(
    () => client.cardPlan(20_000, 4),
    Error,
    "parcelas",
  );
  assertEquals(quotes, 2);
});

Deno.test("CHAR_ é consultado em GET /orders?charge_id e escolhe o pedido certo", async () => {
  const urls: string[] = [];
  const client = provider((url, init) => {
    urls.push(`${init?.method ?? "GET"} ${url}`);
    const headers = new Headers(init?.headers);
    assertEquals(init?.method, "GET");
    assertEquals(headers.get("Accept"), "application/json");
    assertEquals(headers.get("Content-Type"), null);
    assert(headers.get("Authorization")?.startsWith("Bearer "));
    return Promise.resolve(new Response(JSON.stringify({
      orders: [
        {
          id: "ORDE_OUTRO",
          charges: [{
            id: "CHAR_OUTRO",
            status: "WAITING",
            amount: { value: 100 },
            payment_method: { type: "PIX" },
          }],
        },
        {
          id: "ORDE_CERTO",
          charges: [{
            id: "CHAR_CERTO",
            status: "PAID",
            amount: { value: 500 },
            payment_method: { type: "PIX" },
          }],
        },
      ],
    }), { status: 200 }));
  });
  const view = await client.getPayment("CHAR_CERTO");
  assertEquals(view.id, "CHAR_CERTO");
  assertEquals(view.status, "CONFIRMED");
  assert(urls[0].includes("/orders?charge_id=CHAR_CERTO"));
  assert(!urls[0].includes("/charges/CHAR_CERTO"));
});

Deno.test("consulta recusada, ausente ou lenta vira status PagBank", async () => {
  const refused = provider(() =>
    Promise.resolve(new Response("Not Acceptable", { status: 406 }))
  );
  await assertRejects(
    () => refused.getPayment("CHAR_RECUSADO"),
    Error,
    "PagBank 406",
  );
  const missing = provider(() =>
    Promise.resolve(new Response("não", { status: 404 }))
  );
  await assertRejects(
    () => missing.getPayment("ORDE_SUMIU"),
    Error,
    "PagBank 404",
  );
  const empty = provider(() =>
    Promise.resolve(new Response(JSON.stringify({ orders: [] }), { status: 200 }))
  );
  await assertRejects(
    () => empty.getPayment("CHAR_VAZIO"),
    Error,
    "PagBank 404",
  );
  const slow = provider(() =>
    Promise.reject(new DOMException("The signal has been aborted", "TimeoutError"))
  );
  await assertRejects(
    () => slow.getPayment("ORDE_LENTO"),
    Error,
    "PagBank 408: timeout",
  );
});

Deno.test("CHAR_ em pedido com duas cobranças devolve a do id", async () => {
  const order = {
    orders: [{
      id: "ORDE_DUPLO",
      charges: [
        {
          id: "CHAR_RECUSADA",
          status: "DECLINED",
          amount: { value: 1000, currency: "BRL" },
          payment_method: { type: "CREDIT_CARD" },
        },
        {
          id: "CHAR_APROVADA",
          status: "PAID",
          amount: { value: 2500, currency: "BRL" },
          payment_method: { type: "CREDIT_CARD" },
        },
      ],
    }],
  };
  const client = provider(() =>
    Promise.resolve(new Response(JSON.stringify(order), { status: 200 }))
  );
  const paid = await client.readPayment("CHAR_APROVADA");
  assertEquals(paid.id, "CHAR_APROVADA");
  assertEquals(paid.status, "PAID");
  assertEquals((paid.amount as { value: number }).value, 2500);
  const view = await client.getPayment("CHAR_APROVADA");
  assertEquals(view.id, "CHAR_APROVADA");
  assertEquals(view.status, "CONFIRMED");
  const declined = await client.getPayment("CHAR_RECUSADA");
  assertEquals(declined.status, "CANCELED");
  await assertRejects(
    () => client.getPayment("CHAR_FORA"),
    Error,
    "PagBank 404",
  );
});
