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
  assertEquals(pix.payload, "000201PIX");
  assertEquals(pix.splitId, "SPLI_1");
  assertEquals(pix.status, "PENDING");
  const post = calls.find((call) => call.init.method === "POST");
  assert(post);
  assert(post.url.endsWith("/orders"));
  const body = JSON.parse(String(post.init.body));
  const charge = body.charges[0];
  assertEquals(charge.payment_method.type, "PIX");
  assertEquals(charge.payment_method.capture, undefined);
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

Deno.test("4x soma o juro cotado e não aumenta a casa", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
    if (url.includes("/charges/fees/calculate")) {
      return Promise.resolve(new Response(JSON.stringify({
        payment_methods: {
          credit_card: {
            visa: {
              installment_plans: [{
                installments: 4,
                interest_free: false,
                amount: {
                  value: 20640,
                  fees: { buyer: { interest: { total: 640, installments: 1 } } },
                },
              }],
            },
          },
        },
      }), { status: 200 }));
    }
    if ((init?.method ?? "GET") === "POST") {
      const posted = JSON.parse(String(init?.body));
      const charge = posted.charges[0];
      assertEquals(charge.amount.value, 20640);
      assertEquals(charge.amount.fees.buyer.interest.total, 640);
      assertEquals(charge.splits.receivers[0].amount.value, 15000);
      assertEquals(charge.splits.receivers[1].amount.value, 5640);
      return Promise.resolve(new Response(JSON.stringify({
        charges: [{ id: "CHAR_4", status: "AUTHORIZED", splits: { id: "SPLI_4" } }],
      }), { status: 200 }));
    }
    return Promise.resolve(new Response("não", { status: 500 }));
  };
  await provider(fetchFn).authorizeCard({
    customer: "PB_CUS_1",
    value: 200,
    dueDate: "2026-11-07",
    description: "EscapeMatch",
    externalReference: "card-4",
    split: { walletId: venue, fixedValue: 150 },
    creditCardToken: "CARD_1",
    installments: 4,
  });
  assert(calls.some((call) => call.includes("/charges/fees/calculate")));
});

Deno.test("captura, estorno e custódia usam os caminhos da PagBank", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
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
    if (url.endsWith("/release-custody")) {
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
    call.endsWith("/splits/SPLI_1/release-custody")
  ));
  const release = calls.find((call) => call.includes("release-custody"));
  assert(release);
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

Deno.test("abaixo de R$ 150 o cartão não parcela e a casa não perde a taxa", async () => {
  let posted = 0;
  const fetchFn = () => {
    posted += 1;
    return Promise.resolve(new Response("{}", { status: 500 }));
  };
  await assertRejects(
    () =>
      provider(fetchFn).authorizeCard({
        customer: "PB_CUS_1",
        value: 149.99,
        dueDate: "2026-11-07",
        description: "EscapeMatch",
        externalReference: "card-baixo",
        split: { walletId: venue, fixedValue: 100 },
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
    if (url.endsWith("/release-custody")) {
      return Promise.resolve(new Response("", { status: 200 }));
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
  assert(calls.some((call) => call.endsWith("/splits/SPLI_OK/release-custody")));
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
