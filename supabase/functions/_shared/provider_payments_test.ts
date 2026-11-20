import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { commissionCents } from "./scape_points.ts";
import { createAlternateCharge } from "./alternate_charge.ts";
import { cardAuthWindowMs, planCardHold } from "./card_hold.ts";
import { MercadoPagoProvider, mapMpStatus, mpEnvMode, mpPlatformFallback, mpSignatureMatches, mpWebhookManifest, parseSignatureHeader, shouldRefreshOauth, storedCardStatus } from "./mercadopago_provider.ts";
import {
  groupUnconfirmedNotice,
  houseDebitForRefund,
  isHistoricalAsaas,
  providerForBilling,
  wooviSplits,
} from "./payment_provider.ts";
import { buildReadiness } from "./payments_readiness.ts";
import { handleMpWebhook, handleWooviWebhook, verifyWooviWebhook } from "./provider_webhooks.ts";
import { refundAlternate } from "./provider_dispatch.ts";
import { wooviHouseWithdraw } from "./provider_house.ts";
import { signState, verifyState } from "./mp_oauth.ts";
import { WooviProvider } from "./woovi_provider.ts";
import { createCharge } from "../create-charge/index.ts";

const phrase = "Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.";

Deno.test("a frase do grupo fica exata e a flag nasce no Asaas", () => {
  assertEquals(groupUnconfirmedNotice, phrase);
  assertEquals(phrase.includes("nada é cobrado"), false);
  assertEquals(providerForBilling("PIX"), "woovi");
  assertEquals(providerForBilling("CREDIT_CARD"), "mercadopago");
  assertEquals(isHistoricalAsaas("asaas"), true);
  assertEquals(isHistoricalAsaas("woovi"), false);
});

Deno.test("o split Woovi manda a parte da casa e a reserva que cabe", () => {
  const lines = wooviSplits({
    housePixKey: "casa@pix",
    houseCents: 8000,
    chargeCents: 10000,
    reservePixKey: "reserva@pix",
    referralCents: 250,
  });
  assertEquals(lines[0], {
    pixKey: "casa@pix",
    valueCents: 8000,
    splitType: "SPLIT_SUB_ACCOUNT",
  });
  assertEquals(lines[1].pixKey, "reserva@pix");
  assertEquals(lines[1].valueCents, 250);
  assertEquals(
    wooviSplits({
      housePixKey: "casa@pix",
      houseCents: 8000,
      chargeCents: 10000,
      reservePixKey: "reserva@pix",
      referralCents: 3000,
    }).length,
    1,
  );
});

Deno.test("o débito da subconta acompanha o estorno total e o parcial", () => {
  assertEquals(houseDebitForRefund({
    refundCents: 10000,
    chargeCents: 10000,
    houseSplitCents: 8000,
  }), 8000);
  assertEquals(houseDebitForRefund({
    refundCents: 5000,
    chargeCents: 10000,
    houseSplitCents: 8000,
  }), 4000);
});

Deno.test("a reserva do cartão só abre perto da decisão", () => {
  const decision = new Date("2026-12-01T18:00:00.000Z");
  const early = new Date(decision.getTime() - cardAuthWindowMs);
  const inside = new Date(decision.getTime() - 2 * 24 * 60 * 60 * 1000);
  assertEquals(planCardHold(early, decision).authorizeNow, false);
  assertEquals(planCardHold(inside, decision).authorizeNow, true);
  const soon = shouldRefreshOauth(
    new Date(Date.now() + 10 * 24 * 60 * 60 * 1000),
    new Date(),
  );
  const fresh = shouldRefreshOauth(
    new Date(Date.now() + 100 * 24 * 60 * 60 * 1000),
    new Date(),
  );
  assertEquals(soon, true);
  assertEquals(fresh, false);
});

Deno.test("Woovi cobra, saca e estorna com débito da subconta", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    const method = init?.method ?? "GET";
    if (method === "POST" && url.endsWith("/api/v1/charge")) {
      return Promise.resolve(new Response(JSON.stringify({
        charge: {
          correlationID: "charge-1",
          status: "ACTIVE",
          brCode: "000201PIX",
          qrCodeImage: "aW1n",
        },
      })));
    }
    if (method === "POST" && url.endsWith("/api/v1/refund")) {
      return Promise.resolve(new Response(JSON.stringify({
        refund: { correlationID: "refund-1", status: "PROCESSING" },
      })));
    }
    if (url.endsWith("/debit")) {
      return Promise.resolve(new Response(JSON.stringify({ success: "ok" })));
    }
    if (url.endsWith("/withdraw")) {
      return Promise.resolve(new Response(JSON.stringify({
        withdrawal: { status: "success", value: 8000 },
      })));
    }
    if (method === "GET" && url.includes("/subaccount/")) {
      return Promise.resolve(new Response(JSON.stringify({
        SubAccount: { pixKey: "casa@pix", balance: 8000 },
      })));
    }
    if (method === "DELETE") {
      return Promise.resolve(new Response(null, { status: 200 }));
    }
    return Promise.resolve(new Response("nao", { status: 500 }));
  };
  const provider = new WooviProvider(
    "app-id-secreto",
    "https://api.woovi-sandbox.com",
    fetchFn,
  );
  const pix = await provider.createPix({
    correlationId: "charge-1",
    valueCents: 10000,
    comment: phrase,
    splits: wooviSplits({
      housePixKey: "casa@pix",
      houseCents: 8000,
      chargeCents: 10000,
    }),
  });
  assertEquals(pix.brCode, "000201PIX");
  const post = calls[0];
  const body = JSON.parse(String(post.init.body));
  assertEquals(body.value, 10000);
  assertEquals(body.splits[0].splitType, "SPLIT_SUB_ACCOUNT");
  assertEquals(body.splits[0].pixKey, "casa@pix");
  assertEquals(body.splits[0].value, 8000);
  assertEquals((post.init.headers as Record<string, string>).Authorization, "app-id-secreto");
  assertEquals(JSON.stringify(body).includes("app-id-secreto"), false);

  assertEquals(await provider.balance("casa@pix"), 8000);
  const withdrawn = await provider.withdraw("casa@pix", 8000);
  assertEquals(withdrawn.valueCents, 8000);

  await provider.refund({
    providerRef: "charge-1",
    valueCents: 5000,
    chargeCents: 10000,
    correlationId: "refund-parcial",
    endToEndId: "E2E123",
    housePixKey: "casa@pix",
    houseDebitCents: houseDebitForRefund({
      refundCents: 5000,
      chargeCents: 10000,
      houseSplitCents: 8000,
    }),
  });
  const refund = calls.find((call) => call.url.endsWith("/api/v1/refund"));
  const debit = calls.find((call) => call.url.endsWith("/debit"));
  assert(refund);
  assert(debit);
  assertEquals(JSON.parse(String(refund.init.body)).value, 5000);
  assertEquals(JSON.parse(String(refund.init.body)).comment, phrase);
  assertEquals(JSON.parse(String(debit.init.body)).value, 4000);
  await provider.cancelAuthorization("charge-1");
  assert(calls.some((call) => call.init.method === "DELETE"));
});

Deno.test("Mercado Pago reserva sem capturar, captura, cancela e estorna", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    const method = init?.method ?? "GET";
    if (method === "POST" && url.endsWith("/v1/payments")) {
      return Promise.resolve(new Response(JSON.stringify({
        id: 99,
        status: "authorized",
        captured: false,
      })));
    }
    if (method === "PUT" && String(init?.body).includes("capture")) {
      return Promise.resolve(new Response(JSON.stringify({
        id: 99,
        status: "approved",
        captured: true,
      })));
    }
    if (method === "PUT") {
      return Promise.resolve(new Response(JSON.stringify({
        id: 99,
        status: "cancelled",
        captured: false,
      })));
    }
    if (url.endsWith("/refunds")) {
      return Promise.resolve(new Response(JSON.stringify({ id: 7, status: "approved" })));
    }
    return Promise.resolve(new Response(JSON.stringify({
      id: 99,
      status: "authorized",
      captured: false,
    })));
  };
  const provider = new MercadoPagoProvider(fetchFn);
  await assertRejects(
    () => provider.authorizeCard({
      token: "4111111111111111",
      paymentMethodId: "visa",
      transactionAmountCents: 10000,
      applicationFeeCents: 2000,
      description: "sessao",
      payerEmail: "a@b.co",
      idempotencyKey: "idem-1234",
      accessToken: "TEST-token-da-casa-123456",
    }),
    Error,
    "cartão",
  );
  const authorized = await provider.authorizeCard({
    token: "tok_aparelho",
    paymentMethodId: "visa",
    transactionAmountCents: 10000,
    applicationFeeCents: commissionCents(10000, 2000),
    description: "sessao",
    payerEmail: "a@b.co",
    idempotencyKey: "idem-1234",
    accessToken: "TEST-token-da-casa-123456",
  });
  assertEquals(authorized.status, "authorized");
  const created = JSON.parse(String(calls.at(-1)?.init.body));
  assertEquals(created.capture, false);
  assertEquals(created.application_fee, 20);
  assertEquals(created.transaction_amount, 100);
  assertEquals(created.token, "tok_aparelho");
  assertEquals(JSON.stringify(created).includes("4111"), false);
  const headers = calls.at(-1)?.init.headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer TEST-token-da-casa-123456");

  const captured = await provider.capture("99", "TEST-token-da-casa-123456");
  assertEquals(captured.status, "paid");
  const cancelled = await provider.cancelAuthorization("99", "TEST-token-da-casa-123456");
  assertEquals(cancelled.status, "cancelled");
  await provider.refund({
    providerRef: "99",
    valueCents: 2500,
    chargeCents: 10000,
    correlationId: "refund-mp",
    accessToken: "TEST-token-da-casa-123456",
  });
  const refund = calls.find((call) => call.url.endsWith("/refunds"));
  assertEquals(JSON.parse(String(refund?.init.body)).amount, 25);
});

Deno.test("o estorno Woovi do despacho debita a subconta", async () => {
  const debits: unknown[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    if (url.endsWith("/debit")) debits.push(JSON.parse(String(init?.body)));
    if (url.endsWith("/api/v1/refund")) {
      return Promise.resolve(new Response(JSON.stringify({
        refund: { correlationID: "r", status: "PROCESSING" },
      })));
    }
    return Promise.resolve(new Response(JSON.stringify({ success: "ok" })));
  };
  let phase = "refund";
  await refundAlternate(
    {
      rpc(fn: string) {
        if (fn === "claim_provider_refund") {
          return Promise.resolve({ data: phase, error: null });
        }
        if (fn === "mark_provider_refund_recorded") {
          phase = "debit";
          return Promise.resolve({ data: true, error: null });
        }
        if (fn === "mark_provider_debit_done") {
          phase = "done";
          return Promise.resolve({ data: true, error: null });
        }
        return Promise.resolve({ data: null, error: null });
      },
    },
    {
      id: "c1",
      group_id: "g1",
      user_id: "u1",
      venue_id: "v1",
      amount_cents: 10000,
      commission_bps: 2000,
      status: "paid",
      provider: "woovi",
      provider_ref: "charge-1",
      billing_type: "PIX",
      provider_end_to_end_id: "E2E999",
      house_pix_key: "casa@pix",
      house_fixed_cents: 8000,
    },
    {
      woovi: new WooviProvider("app", "https://api.woovi-sandbox.com", fetchFn),
    },
    10000,
  );
  assertEquals(debits, [{ value: 8000, description: "Estorno" }]);
});

Deno.test("create-charge no trilho woovi não chama o Asaas", async () => {
  const calls: string[] = [];
  const fetchFn = (url: string) => {
    calls.push(url);
    return Promise.resolve(new Response(JSON.stringify({
      charge: {
        correlationID: "idem-woovi-1",
        status: "ACTIVE",
        brCode: "000201PIX",
        qrCodeImage: "aW1n",
      },
    })));
  };
  const inserted: Record<string, unknown>[] = [];
  const response = await createCharge(request(), {
    user: { id: "user-1", email: "a@b.co" },
    admin: fakeAdmin(inserted),
    now: new Date("2026-11-20T12:00:00.000Z"),
    env: {
      get: (name) => name === "WOOVI_APP_ID" ? "app-id" : "",
    },
    woovi: new WooviProvider("app-id", "https://api.woovi-sandbox.com", fetchFn),
  });
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.provider, "woovi");
  assertEquals(body.notice, phrase);
  assertEquals(body.qr_code, "000201PIX");
  assertEquals(calls.length, 1);
  assertEquals(String(calls[0]).includes("/api/v1/charge"), true);
  assertEquals(inserted[0].provider, "woovi");
  assertEquals(inserted[0].house_fixed_cents, 8000);
  assertEquals(inserted[0].house_pix_key, "casa@pix");
});

Deno.test("cartão longe da decisão não reserva no Mercado Pago", async () => {
  let called = false;
  const response = await createAlternateCharge({
    json: (body, status = 200) => Response.json(body, { status }),
    admin: fakeAdmin([]),
    user: { id: "user-1", email: "a@b.co" },
    group: {
      venue_id: "venue-1",
      price_cents: 10000,
      closes_at: "2027-06-01T18:00:00.000Z",
      starts_at: "2027-06-01T18:00:00.000Z",
    },
    existing: null,
    body: {
      billing_type: "CREDIT_CARD",
      card_token: "tok_aparelho",
      payment_method_id: "visa",
    },
    groupId: "group-1",
    billingType: "CREDIT_CARD",
    idempotencyKey: "idem-card-1",
    now: new Date("2026-11-20T12:00:00.000Z"),
    env: { get: () => "" },
    mercadoPago: new MercadoPagoProvider(() => {
      called = true;
      return Promise.resolve(new Response("{}", { status: 500 }));
    }),
  });
  const body = await response.json();
  assertEquals(response.status, 409);
  assertEquals(body.error, "card_hold_deferred");
  assertEquals(body.notice, phrase);
  assertEquals(called, false);
});

Deno.test("webhook Woovi exige assinatura e é idempotente", async () => {
  const secret = "webhook-secret-woovi-32chars";
  const raw = JSON.stringify({
    event: "OPENPIX:CHARGE_COMPLETED",
    charge: { correlationID: "idem-woovi-1", status: "COMPLETED" },
    pix: { endToEndId: "E2E999" },
  });
  const header = await hmac(raw, secret);
  assertEquals(await verifyWooviWebhook({
    rawBody: raw,
    hmacHeader: "errado",
    rsaHeader: null,
    secret,
    publicKeys: [],
  }), false);
  assertEquals(await verifyWooviWebhook({
    rawBody: raw,
    hmacHeader: header,
    rsaHeader: null,
    secret,
    publicKeys: [],
  }), true);

  const seen: string[] = [];
  const admin = webhookAdmin(seen);
  const req = new Request("https://exemplo.test/woovi-webhook", {
    method: "POST",
    headers: { "x-openpix-signature": header },
    body: raw,
  });
  const env = { get: (name: string) => name === "WOOVI_WEBHOOK_SECRET" ? secret : "" };
  const first = await handleWooviWebhook(req, { env, admin, rawBody: raw });
  const second = await handleWooviWebhook(req, { env, admin, rawBody: raw });
  assertEquals(first.status, 200);
  assertEquals((await second.json()).duplicate, true);
  assertEquals(seen.length, 1);
  assertEquals(seen[0], "paid");
});

Deno.test("webhook do Mercado Pago confere o manifest", async () => {
  const secret = "mp-webhook-secret-32chars";
  const dataId = "99";
  const requestId = "req-1";
  const ts = "1700000000";
  const manifest = mpWebhookManifest({ dataId, requestId, ts });
  const v1 = await hmac(manifest, secret);
  const header = `ts=${ts},v1=${v1}`;
  assertEquals(parseSignatureHeader(header).v1, v1);
  assertEquals(await mpSignatureMatches({ secret, manifest, v1 }), true);
  assertEquals(await mpSignatureMatches({ secret, manifest, v1: "00" }), false);

  const raw = JSON.stringify({
    id: "evt-1",
    action: "payment.updated",
    data: { id: dataId },
  });
  const seen: string[] = [];
  const admin = webhookAdmin(seen, "mercadopago");
  const fetchFn = () => Promise.resolve(new Response(JSON.stringify({
    id: 99,
    status: "approved",
    captured: true,
  })));
  const env = {
    get: (name: string) => {
      if (name === "MP_WEBHOOK_SECRET") return secret;
      if (name === "MP_ACCESS_TOKEN") return "TEST-token-da-casa-123456";
      return "";
    },
  };
  const response = await handleMpWebhook(
    new Request(`https://exemplo.test/mp-webhook?data.id=${dataId}`, {
      method: "POST",
      headers: {
        "x-signature": header,
        "x-request-id": requestId,
      },
      body: raw,
    }),
    { env, admin, rawBody: raw, fetchFn },
  );
  assertEquals(response.status, 200);
  assertEquals(seen, ["paid"]);
  const again = await handleMpWebhook(
    new Request(`https://exemplo.test/mp-webhook?data.id=${dataId}`, {
      method: "POST",
      headers: { "x-signature": header, "x-request-id": requestId },
      body: raw,
    }),
    { env, admin, rawBody: raw, fetchFn },
  );
  assertEquals((await again.json()).duplicate, true);
  assertEquals(seen.length, 1);
});

Deno.test("a prontidão por provedor não devolve segredo", () => {
  const secret = "super-segredo-nao-vazar";
  const report = buildReadiness({
    get: (name) => {
      if (name === "PAYMENTS_PROVIDER") return "woovi";
      if (name === "WOOVI_APP_ID") return secret;
      if (name === "WOOVI_BASE_URL") return "https://api.woovi-sandbox.com";
      if (name === "WOOVI_WEBHOOK_SECRET") return secret;
      if (name === "MP_CLIENT_ID") return "client";
      if (name === "MP_CLIENT_SECRET") return secret;
      if (name === "MP_WEBHOOK_SECRET") return secret;
      if (name === "MP_OAUTH_REDIRECT_URI") return "https://parceiro.scapematch.com.br/mp";
      if (name === "MP_ACCESS_TOKEN") return "TEST-token-da-casa-123456";
      return "";
    },
  }, {});
  assertEquals(report.payments_provider, "woovi");
  assertEquals(report.woovi_app_id, true);
  assertEquals(report.woovi_base_url_sandbox, true);
  assertEquals(report.woovi_webhook_secret, true);
  assertEquals(report.mp_client_secret, true);
  assertEquals(report.mp_env_sandbox, false);
  assertEquals(report.mp_access_token_test, true);
  assertEquals(JSON.stringify(report).includes(secret), false);
  assertEquals(JSON.stringify(report).includes("TEST-token"), false);
});

function request(): Request {
  return new Request("https://exemplo.test/create-charge", {
    method: "POST",
    body: JSON.stringify({
      group_id: "group-1",
      billing_type: "PIX",
      idempotency_key: "idem-woovi-1",
    }),
  });
}

function fakeAdmin(inserted: Record<string, unknown>[]) {
  const tables: Record<string, Record<string, unknown>> = {
    groups: {
      id: "group-1",
      venue_id: "venue-1",
      price_cents: 10000,
      cancelled_at: null,
      starts_at: "2027-06-01T18:00:00.000Z",
      closes_at: "2027-06-01T12:00:00.000Z",
    },
    group_members: { id: "member-1", attendance: "confirmed" },
    venues: { id: "venue-1", name: "Casa", status: "approved" },
    provider_payout_accounts: {
      pix_key: "casa@pix",
      external_id: "casa@pix",
      status: "active",
    },
  };
  return {
    from(table: string) {
      const filters: [string, string][] = [];
      const api = {
        select() {
          return api;
        },
        eq(column: string, value: string) {
          filters.push([column, value]);
          return api;
        },
        maybeSingle() {
          return Promise.resolve({ data: tables[table] ?? null, error: null });
        },
        insert(row: Record<string, unknown>) {
          inserted.push(row);
          return Promise.resolve({ error: null });
        },
        update() {
          return { eq: () => Promise.resolve({ error: null }) };
        },
      };
      return api;
    },
    rpc(name: string) {
      if (name === "commission_bps_for_venue") {
        return Promise.resolve({ data: 2000, error: null });
      }
      if (name === "cap_point_redemption") {
        return Promise.resolve({ data: 0, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
}

function webhookAdmin(
  seen: string[],
  provider = "woovi",
  options: { fail?: boolean } = {},
) {
  const events = new Set<string>();
  const admin = {
    fail: options.fail === true,
    released: [] as string[],
    rpc(fn: string, args: Record<string, unknown>) {
      if (fn === "claim_provider_webhook") {
        const key = `${args.p_provider}:${args.p_event_id}`;
        if (events.has(key)) return Promise.resolve({ data: false, error: null });
        events.add(key);
        return Promise.resolve({ data: true, error: null });
      }
      if (fn === "release_provider_webhook") {
        const key = `${args.p_provider}:${args.p_event_id}`;
        events.delete(key);
        admin.released.push(key);
        return Promise.resolve({ data: true, error: null });
      }
      if (fn === "apply_payment_transition") {
        if (admin.fail) return Promise.reject(new Error("livro"));
        seen.push(String(args.p_next_status));
        return Promise.resolve({
          data: {
            applied: true,
            status: args.p_next_status,
            paid_at: null,
            refunded_at: null,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    },
    from(table: string) {
      const api = {
        select() {
          return api;
        },
        eq() {
          return api;
        },
        neq() {
          return Promise.resolve({ count: 0, error: null });
        },
        maybeSingle() {
          if (table === "payment_charges") {
            return Promise.resolve({
              data: {
                id: "charge-row",
                group_id: "group-1",
                venue_id: "venue-1",
                provider,
              },
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
        update() {
          return { eq: () => Promise.resolve({ error: null }) };
        },
      };
      return api;
    },
  };
  return admin;
}

async function hmac(raw: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(raw),
  );
  return [...new Uint8Array(signed)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

Deno.test("in_process fica pendente e chargeback não é estorno", () => {
  assertEquals(mapMpStatus("in_process"), "pending");
  assertEquals(mapMpStatus("pending"), "pending");
  assertEquals(mapMpStatus("charged_back"), "charged_back");
  assertEquals(mapMpStatus("in_mediation"), "charged_back");
  assertEquals(mapMpStatus("refunded"), "refunded");
  assertEquals(storedCardStatus("pending"), "pending");
  assertEquals(storedCardStatus("in_process"), "failed");
  assertEquals(storedCardStatus(mapMpStatus("in_process")), "pending");
  assertEquals(storedCardStatus("charged_back"), "charged_back");
  assertEquals(storedCardStatus("rejected"), "failed");
});

Deno.test("falha no webhook libera o evento para o reenvio", async () => {
  const secret = "webhook-secret-woovi-32chars";
  const raw = JSON.stringify({
    event: "OPENPIX:CHARGE_COMPLETED",
    charge: { correlationID: "idem-woovi-1", status: "COMPLETED" },
    pix: { endToEndId: "E2E999" },
  });
  const header = await hmac(raw, secret);
  const seen: string[] = [];
  const admin = webhookAdmin(seen, "woovi", { fail: true });
  const env = { get: (name: string) => name === "WOOVI_WEBHOOK_SECRET" ? secret : "" };
  const req = new Request("https://exemplo.test/woovi-webhook", {
    method: "POST",
    headers: { "x-openpix-signature": header },
    body: raw,
  });
  const failed = await handleWooviWebhook(req, { env, admin, rawBody: raw });
  assertEquals(failed.status, 500);
  assertEquals(admin.released.length, 1);
  admin.fail = false;
  const again = await handleWooviWebhook(req, { env, admin, rawBody: raw });
  assertEquals(again.status, 200);
  assertEquals(seen, ["paid"]);
});

Deno.test("o fallback da plataforma segue MP_ENV", () => {
  const appUsr = "APP_USR-token-de-teste-123456";
  const test = "TEST-token-da-casa-123456";
  const env = (vars: Record<string, string>) => ({
    get: (name: string) => vars[name] ?? "",
  });
  assertEquals(mpEnvMode(env({})), "production");
  assertEquals(mpEnvMode(env({ MP_ENV: "SANDBOX" })), "sandbox");
  assertEquals(mpEnvMode(env({ MP_ENV: "teste" })), "production");
  assertEquals(
    mpPlatformFallback(env({ MP_ENV: "sandbox", MP_ACCESS_TOKEN: appUsr })),
    appUsr,
  );
  assertEquals(mpPlatformFallback(env({ MP_ACCESS_TOKEN: appUsr })), null);
  assertEquals(mpPlatformFallback(env({ MP_ACCESS_TOKEN: test })), test);
  assertEquals(
    mpPlatformFallback(env({ MP_ENV: "production", MP_ACCESS_TOKEN: test })),
    null,
  );
  assertEquals(
    mpPlatformFallback(env({ MP_ENV: "sandbox", MP_ACCESS_TOKEN: "curto" })),
    null,
  );

  const sandbox = buildReadiness({
    get: (name: string) => {
      if (name === "MP_ENV") return "sandbox";
      if (name === "MP_ACCESS_TOKEN") return appUsr;
      return "";
    },
  }, {});
  assertEquals(sandbox.mp_env_sandbox, true);
  assertEquals(sandbox.mp_access_token_test, true);
  assertEquals(JSON.stringify(sandbox).includes(appUsr), false);

  const closed = buildReadiness({
    get: (name: string) => name === "MP_ACCESS_TOKEN" ? appUsr : "",
  }, {});
  assertEquals(closed.mp_env_sandbox, false);
  assertEquals(closed.mp_access_token_test, false);
});

Deno.test("mp-webhook em sandbox usa o token APP_USR- da plataforma", async () => {
  const secret = "mp-webhook-secret-32chars";
  const token = "APP_USR-token-de-teste-123456";
  const dataId = "99";
  const requestId = "req-sandbox";
  const ts = "1700000000";
  const manifest = mpWebhookManifest({ dataId, requestId, ts });
  const v1 = await hmac(manifest, secret);
  const raw = JSON.stringify({
    id: "evt-sandbox",
    action: "payment.updated",
    data: { id: dataId },
  });
  const seen: string[] = [];
  const headers: string[] = [];
  const admin = webhookAdmin(seen, "mercadopago");
  const env = {
    get: (name: string) => {
      if (name === "MP_WEBHOOK_SECRET") return secret;
      if (name === "MP_ENV") return "sandbox";
      if (name === "MP_ACCESS_TOKEN") return token;
      return "";
    },
  };
  const response = await handleMpWebhook(
    new Request(`https://exemplo.test/mp-webhook?data.id=${dataId}`, {
      method: "POST",
      headers: { "x-signature": `ts=${ts},v1=${v1}`, "x-request-id": requestId },
      body: raw,
    }),
    {
      env,
      admin,
      rawBody: raw,
      fetchFn: (_url, init) => {
        const sent = new Headers(init?.headers).get("Authorization") ?? "";
        headers.push(sent);
        return Promise.resolve(new Response(JSON.stringify({
          id: 99,
          status: "approved",
          captured: true,
        })));
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(headers, [`Bearer ${token}`]);
  assertEquals(seen, ["paid"]);
});

Deno.test("mp-webhook em produção não usa o token da plataforma", async () => {
  const secret = "mp-webhook-secret-32chars";
  const dataId = "99";
  const requestId = "req-prod";
  const ts = "1700000000";
  const manifest = mpWebhookManifest({ dataId, requestId, ts });
  const v1 = await hmac(manifest, secret);
  const raw = JSON.stringify({ id: "evt-prod", action: "payment.updated", data: { id: dataId } });
  const seen: string[] = [];
  const urls: string[] = [];
  const admin = webhookAdmin(seen, "mercadopago");
  const env = {
    get: (name: string) => {
      if (name === "MP_WEBHOOK_SECRET") return secret;
      if (name === "MP_ACCESS_TOKEN") return "APP_USR-plataforma-nao-usar";
      return "";
    },
  };
  const response = await handleMpWebhook(
    new Request(`https://exemplo.test/mp-webhook?data.id=${dataId}`, {
      method: "POST",
      headers: { "x-signature": `ts=${ts},v1=${v1}`, "x-request-id": requestId },
      body: raw,
    }),
    {
      env,
      admin,
      rawBody: raw,
      fetchFn: (url) => {
        urls.push(url);
        return Promise.resolve(new Response("{}"));
      },
    },
  );
  assertEquals(response.status, 500);
  assertEquals(urls, []);
  assertEquals(admin.released.length, 1);
  assertEquals(seen, []);
});

Deno.test("o state do Mercado Pago muda e vence", async () => {
  const secret = "state-secret-16chars";
  const venueId = "11111111-1111-4111-8111-111111111111";
  const now = new Date("2026-11-20T12:00:00.000Z");
  const first = await signState({
    venueId,
    secret,
    nonce: "a".repeat(32),
    expiresAt: now.getTime() + 60_000,
  });
  const second = await signState({
    venueId,
    secret,
    nonce: "b".repeat(32),
    expiresAt: now.getTime() + 60_000,
  });
  assert(first !== second);
  assertEquals(await verifyState({ state: first, venueId, secret, now }), true);
  assertEquals(await verifyState({
    state: first,
    venueId,
    secret,
    now: new Date(now.getTime() + 11 * 60 * 1000),
  }), false);
  assertEquals(await verifyState({
    state: `${venueId}.assinatura-fixa`,
    venueId,
    secret,
    now,
  }), false);
});

Deno.test("o saque manual não lê o saldo da subconta", async () => {
  const urls: string[] = [];
  const fetchFn = (url: string) => {
    urls.push(url);
    return Promise.resolve(new Response(JSON.stringify({
      withdrawal: { status: "success", value: 3000 },
      SubAccount: { balance: 999999 },
    })));
  };
  const result = await wooviHouseWithdraw({
    env: { get: (name: string) => name === "WOOVI_APP_ID" ? "app" : name === "WOOVI_BASE_URL" ? "https://api.woovi-sandbox.com" : "" },
    fetchFn,
    store: {
      rpc(fn: string, args: Record<string, unknown>) {
        if (fn === "provider_house_account") {
          return Promise.resolve({ pix_key: "casa@pix", status: "active" });
        }
        if (fn === "claim_provider_withdrawal") {
          assertEquals(args.p_amount_cents, 3000);
          assertEquals(args.p_available_cents, 0);
          return Promise.resolve({
            id: "11111111-1111-4111-8111-111111111111",
            amount_cents: 3000,
          });
        }
        if (fn === "begin_withdrawal_dispatch") return Promise.resolve(true);
        if (fn === "attach_venue_transfer") return Promise.resolve(true);
        return Promise.resolve(null);
      },
    },
  }, {
    venueId: "22222222-2222-4222-8222-222222222222",
    actorId: "33333333-3333-4333-8333-333333333333",
    amountCents: 3000,
  });
  assertEquals(result.status, 200);
  assertEquals(urls.some((url) => url.includes("/subaccount/") && !url.endsWith("/withdraw")), false);
  assert(urls.some((url) => url.endsWith("/withdraw")));
});

Deno.test("débito da subconta falho não estorna o Pix de novo", async () => {
  const refunds: string[] = [];
  let phase = "refund";
  const fetchFn = (url: string, init?: RequestInit) => {
    if (url.endsWith("/api/v1/refund")) {
      refunds.push(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        refund: { correlationID: "r", status: "PROCESSING" },
      })));
    }
    if (url.endsWith("/debit")) {
      return Promise.resolve(new Response("falhou", { status: 500 }));
    }
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const admin = {
    rpc(fn: string) {
      if (fn === "claim_provider_refund") {
        return Promise.resolve({ data: phase, error: null });
      }
      if (fn === "mark_provider_refund_recorded") {
        phase = "debit";
        return Promise.resolve({ data: true, error: null });
      }
      if (fn === "release_provider_refund") {
        phase = "refund";
        return Promise.resolve({ data: true, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  const row = {
    id: "c1",
    group_id: "g1",
    user_id: "u1",
    venue_id: "v1",
    amount_cents: 10000,
    commission_bps: 2000,
    status: "paid",
    provider: "woovi",
    provider_ref: "charge-1",
    billing_type: "PIX",
    provider_end_to_end_id: "E2E999",
    house_pix_key: "casa@pix",
    house_fixed_cents: 8000,
  };
  const gate = {
    woovi: new WooviProvider("app", "https://api.woovi-sandbox.com", fetchFn),
  };
  await refundAlternate(admin, row, gate, 10000);
  await refundAlternate(admin, row, gate, 10000);
  assertEquals(refunds.length, 1);
  assertEquals(phase, "debit");
});
