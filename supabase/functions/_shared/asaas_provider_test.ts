import { assertEquals, assert } from "jsr:@std/assert@1";
import {
  AsaasProvider,
  commissionCents,
  houseSplitPercent,
  tokensMatch,
} from "./asaas_provider.ts";

Deno.test("10% de comissão deixa 90% com a casa", () => {
  assertEquals(houseSplitPercent(1000), 90);
  assertEquals(houseSplitPercent(0), 100);
  assertEquals(houseSplitPercent(1500), 85);
  assertEquals(commissionCents(12000, 1000), 1200);
});

Deno.test("o Pix manda o split para o walletId e a chave só no header", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    if (url.endsWith("/payments")) {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "pay_1", status: "PENDING" }), {
          status: 200,
        }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({ payload: "000201PIX", encodedImage: "aW1n" }),
        { status: 200 },
      ),
    );
  };
  const provider = new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  const pix = await provider.createPix({
    customer: "cus_1",
    value: 120,
    dueDate: "2026-11-07",
    description: "ScapeMatch Demo",
    externalReference: "charge-1",
    split: { walletId: "wal_house", percentualValue: 90 },
  });
  assertEquals(pix.payload, "000201PIX");
  const body = JSON.parse(String(calls[0].init.body));
  assertEquals(body.billingType, "PIX");
  assertEquals(body.split[0].walletId, "wal_house");
  assertEquals(body.split[0].percentualValue, 90);
  assertEquals(JSON.stringify(body).includes("asaas-secret-key"), false);
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers.access_token, "asaas-secret-key");
  assertEquals(calls[1].url.endsWith("/payments/pay_1/pixQrCode"), true);
  assertEquals(calls[1].init.method, "GET");
  assertEquals(calls[1].init.body, undefined);
});

Deno.test("o cartão reserva com authorizeOnly e a captura usa o endpoint oficial", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    return Promise.resolve(
      new Response(JSON.stringify({ id: "pay_card", status: "AUTHORIZED" }), {
        status: 200,
      }),
    );
  };
  const provider = new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  await provider.authorizeCard({
    customer: "cus_1",
    value: 80,
    dueDate: "2026-11-07",
    description: "reserva",
    externalReference: "charge-2",
    split: { walletId: "wal_house", percentualValue: 90 },
    remoteIp: "177.0.0.1",
    creditCard: {
      holderName: "ANA",
      number: "4111111111111111",
      expiryMonth: "12",
      expiryYear: "2028",
      ccv: "123",
    },
    creditCardHolderInfo: {
      name: "ANA",
      email: "ana@example.com",
      cpfCnpj: "39053344705",
      postalCode: "80020310",
      addressNumber: "100",
      phone: "41999990000",
    },
  });
  const body = JSON.parse(String(calls[0].init.body));
  assertEquals(body.authorizeOnly, true);
  assertEquals(body.billingType, "CREDIT_CARD");
  await provider.capture("pay_card");
  assert(
    calls[1].url.endsWith("/payments/pay_card/captureAuthorizedPayment"),
  );
  await provider.refund("pay_card");
  assert(calls[2].url.endsWith("/payments/pay_card/refund"));
});

Deno.test("a subconta devolve só o walletId", async () => {
  const fetchFn = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({ apiKey: "sub-secret", walletId: "wal_demo" }),
        { status: 200 },
      ),
    );
  const provider = new AsaasProvider(
    "root-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  const created = await provider.createSubaccount({
    name: "ScapeMatch Demo",
    email: "demo@example.com",
    cpfCnpj: "04252011000110",
    companyType: "LIMITED",
    phone: "41999990000",
    mobilePhone: "41999990000",
    incomeValue: 5000,
    address: "Rua XV de Novembro",
    addressNumber: "100",
    province: "Centro",
    postalCode: "80020310",
  });
  assertEquals(created, { walletId: "wal_demo" });
  assertEquals(JSON.stringify(created).includes("sub-secret"), false);
});

Deno.test("webhook sem o token certo é recusado", () => {
  assertEquals(tokensMatch("a".repeat(32), "a".repeat(32)), true);
  assertEquals(tokensMatch("a".repeat(32), "b".repeat(32)), false);
  assertEquals(tokensMatch(null, "a".repeat(32)), false);
  assertEquals(tokensMatch("a".repeat(32), undefined), false);
  assertEquals(tokensMatch("short", "short"), false);
});
