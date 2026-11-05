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

const sampleCard = {
  holderName: "ANA",
  number: "4111111111111111",
  expiryMonth: "12",
  expiryYear: "2028",
  ccv: "999",
};

const sampleHolder = {
  name: "ANA",
  email: "ana@example.com",
  cpfCnpj: "39053344705",
  postalCode: "80020310",
  addressNumber: "100",
  phone: "41999990000",
};

const sampleCharge = {
  customer: "cus_1",
  value: 80,
  dueDate: "2026-11-07",
  description: "reserva",
  externalReference: "charge-2",
  split: { walletId: "wal_house", percentualValue: 90 },
  remoteIp: "177.0.0.1",
};

Deno.test("a primeira cobrança tokeniza e só então reserva com o token", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    if (url.endsWith("/creditCard/tokenizeCreditCard")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            creditCardToken: "tok_card_1",
            creditCardNumber: "1111",
            creditCardBrand: "VISA",
          }),
          { status: 200 },
        ),
      );
    }
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
  const tokenized = await provider.tokenizeCard({
    customer: sampleCharge.customer,
    remoteIp: sampleCharge.remoteIp,
    creditCard: sampleCard,
    creditCardHolderInfo: sampleHolder,
  });
  const authorized = await provider.authorizeCard({
    ...sampleCharge,
    creditCardToken: tokenized.creditCardToken,
  });
  assertEquals(tokenized.creditCardToken, "tok_card_1");
  assertEquals(authorized.id, "pay_card");
  assert(calls[0].url.endsWith("/creditCard/tokenizeCreditCard"));
  const tokenBody = JSON.parse(String(calls[0].init.body));
  assertEquals(tokenBody.creditCard.number, sampleCard.number);
  const payment = JSON.parse(String(calls[1].init.body));
  assertEquals(payment.authorizeOnly, true);
  assertEquals(payment.billingType, "CREDIT_CARD");
  assertEquals(payment.creditCardToken, "tok_card_1");
  assertEquals(payment.split[0].walletId, "wal_house");
  assertEquals(payment.split[0].percentualValue, 90);
  assertEquals(payment.creditCard, undefined);
  assertEquals(payment.creditCardHolderInfo, undefined);
  const paymentText = JSON.stringify(payment);
  assertEquals(paymentText.includes(sampleCard.number), false);
  assertEquals(paymentText.includes(sampleCard.ccv), false);
  assertEquals(paymentText.includes(sampleCard.expiryMonth), false);
  assertEquals(paymentText.includes(sampleCard.expiryYear), false);
  await provider.capture("pay_card");
  assert(
    calls[2].url.endsWith("/payments/pay_card/captureAuthorizedPayment"),
  );
  await provider.refund("pay_card");
  assert(calls[3].url.endsWith("/payments/pay_card/refund"));
  await provider.cancelAuthorization("pay_card");
  assertEquals(calls[4].init.method, "DELETE");
  assert(calls[4].url.endsWith("/payments/pay_card"));
});

Deno.test("com token a cobrança não reenvia o cartão", async () => {
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
    ...sampleCharge,
    creditCardToken: "tok_card_1",
  });
  assertEquals(calls.length, 1);
  assert(calls[0].url.endsWith("/payments"));
  const payment = JSON.parse(String(calls[0].init.body));
  assertEquals(payment.creditCardToken, "tok_card_1");
  assertEquals(payment.authorizeOnly, true);
  assertEquals(JSON.stringify(payment).includes(sampleCard.number), false);
  assertEquals(JSON.stringify(payment).includes(sampleCard.ccv), false);
});

Deno.test("erro da tokenização não ecoa número, CVV, validade nem o body", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const echoed = JSON.stringify({
    errors: [{
      description:
        `cartão ${sampleCard.number} pedido 12 ref ${sampleCard.ccv} vence 2026-11-12`,
    }],
    creditCard: sampleCard,
  });
  const fetchFn = () =>
    Promise.resolve(new Response(echoed, { status: 400 }));
  const provider = new AsaasProvider(
    "asaas-secret-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  let message = "";
  try {
    await provider.tokenizeCard({
      customer: sampleCharge.customer,
      remoteIp: sampleCharge.remoteIp,
      creditCard: sampleCard,
      creditCardHolderInfo: sampleHolder,
    });
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  } finally {
    console.error = original;
  }
  assert(message.length > 0);
  assertEquals(message.includes(sampleCard.number), false);
  assertEquals(message.includes("4111"), false);
  assertEquals(message.includes(`"ccv":"${sampleCard.ccv}"`), false);
  assertEquals(message.includes(`"expiryMonth":"${sampleCard.expiryMonth}"`), false);
  assertEquals(message.includes(`"expiryYear":"${sampleCard.expiryYear}"`), false);
  assertEquals(message.includes(`"number":"${sampleCard.number}"`), false);
  assertEquals(message.includes("pedido 12"), true);
  assertEquals(message.includes(`ref ${sampleCard.ccv}`), true);
  assertEquals(message.includes("2026-11-12"), true);
  assertEquals(logs.length, 0);
});

Deno.test("a subconta devolve walletId e apiKey para a função gravar", async () => {
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
  assertEquals(created.walletId, "wal_demo");
  assertEquals(created.apiKey, "sub-secret");
  assertEquals(provider.sandbox, true);
  assertEquals(
    provider.withKey("sub-secret").sandbox,
    true,
  );
});

Deno.test("a nota usa /invoices e a chave só no header", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    if (url.endsWith("/invoices")) {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "inv_1", status: "SCHEDULED" }), {
          status: 200,
        }),
      );
    }
    if (url.endsWith("/authorize")) {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "inv_1" }), { status: 200 }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          id: "inv_1",
          status: "AUTHORIZED",
          number: "100",
          pdfUrl: "https://asaas.example/n.pdf",
          xmlUrl: "https://asaas.example/n.xml",
        }),
        { status: 200 },
      ),
    );
  };
  const provider = new AsaasProvider(
    "root-key",
    "https://api.asaas.com/v3",
    fetchFn,
  );
  assertEquals(provider.sandbox, false);
  const scheduled = await provider.scheduleInvoice({
    customer: "cus_house",
    serviceDescription: "Comissão de intermediação",
    value: 12,
    deductions: 0,
    effectiveDate: "2026-11-06",
    municipalServiceCode: "17.02",
    municipalServiceName: "Intermediação de reservas",
    externalReference: "commission:ch-1",
    taxes: {
      retainIss: false,
      iss: 2,
      cofins: 0,
      csll: 0,
      inss: 0,
      ir: 0,
      pis: 0,
    },
  });
  assertEquals(scheduled.id, "inv_1");
  const body = JSON.parse(String(calls[0].init.body));
  assertEquals(body.customer, "cus_house");
  assertEquals(body.municipalServiceCode, "17.02");
  assertEquals(body.value, 12);
  assertEquals(JSON.stringify(body).includes("root-key"), false);
  assertEquals(
    (calls[0].init.headers as Record<string, string>).access_token,
    "root-key",
  );
  await provider.authorizeInvoice("inv_1");
  assertEquals(calls[1].url.endsWith("/invoices/inv_1/authorize"), true);
  const view = await provider.getInvoice("inv_1");
  assertEquals(view.pdfUrl, "https://asaas.example/n.pdf");
  assertEquals(view.xmlUrl, "https://asaas.example/n.xml");
  assertEquals(view.number, "100");
});

Deno.test("fiscalInfo vai para /fiscalInfo sem a senha municipal no header", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (url: string, init?: RequestInit) => {
    calls.push({ url, init: init ?? {} });
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const provider = new AsaasProvider(
    "sub-key",
    "https://api-sandbox.asaas.com/v3",
    fetchFn,
  );
  await provider.configureFiscalInfo({
    email: "casa@example.com",
    municipalInscription: "12345678",
    simplesNacional: true,
    cnae: "9329899",
    serviceListItem: "12.08",
    username: "prefeitura",
    password: "segredo-municipal",
  });
  assertEquals(calls[0].url.endsWith("/fiscalInfo"), true);
  const body = JSON.parse(String(calls[0].init.body));
  assertEquals(body.municipalInscription, "12345678");
  assertEquals(body.password, "segredo-municipal");
  assertEquals(body.simplesNacional, true);
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers.access_token, "sub-key");
  assertEquals(JSON.stringify(headers).includes("segredo-municipal"), false);
});

Deno.test("webhook sem o token certo é recusado", () => {
  assertEquals(tokensMatch("a".repeat(32), "a".repeat(32)), true);
  assertEquals(tokensMatch("a".repeat(32), "b".repeat(32)), false);
  assertEquals(tokensMatch(null, "a".repeat(32)), false);
  assertEquals(tokensMatch("a".repeat(32), undefined), false);
  assertEquals(tokensMatch("short", "short"), false);
});
