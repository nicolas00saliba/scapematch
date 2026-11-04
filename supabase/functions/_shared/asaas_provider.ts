// Gateway Asaas. A chave fica só em Deno.env na função que instancia isto.
// Sandbox: https://api-sandbox.asaas.com/v3
// Produção: https://api.asaas.com/v3

export const asaasSandboxBaseUrl = "https://api-sandbox.asaas.com/v3";
export const asaasProductionBaseUrl = "https://api.asaas.com/v3";

export type AsaasFetch = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export type SubaccountInput = {
  name: string;
  email: string;
  cpfCnpj: string;
  companyType?: string;
  birthDate?: string;
  phone: string;
  mobilePhone: string;
  incomeValue: number;
  address: string;
  addressNumber: string;
  province: string;
  postalCode: string;
};

export type CustomerInput = {
  name: string;
  email: string;
  externalReference: string;
  cpfCnpj?: string;
};

export type ChargeSplit = {
  walletId: string;
  percentualValue: number;
};

export type PixInput = {
  customer: string;
  value: number;
  dueDate: string;
  description: string;
  externalReference: string;
  split: ChargeSplit;
};

export type CardInput = PixInput & {
  remoteIp: string;
  creditCard: {
    holderName: string;
    number: string;
    expiryMonth: string;
    expiryYear: string;
    ccv: string;
  };
  creditCardHolderInfo: {
    name: string;
    email: string;
    cpfCnpj: string;
    postalCode: string;
    addressNumber: string;
    phone: string;
  };
};

export type PixCreated = {
  id: string;
  status: string;
  payload: string;
  encodedImage: string;
};

export type PaymentView = {
  id: string;
  status: string;
  billingType: string;
};

/// Percentual do líquido que vai para a casa. A ScapeMatch fica com o resto,
/// que é a comissão em basis points (1000 = 10% → a casa recebe 90).
export function houseSplitPercent(commissionBps: number): number {
  if (
    !Number.isInteger(commissionBps) || commissionBps < 0 ||
    commissionBps > 10000
  ) {
    throw new Error("invalid commission");
  }
  return (10000 - commissionBps) / 100;
}

/// Mesma conta de centavos do pacote dominio (meio centavo sobe).
export function commissionCents(amountCents: number, commissionBps: number): number {
  if (amountCents < 0 || commissionBps < 0 || commissionBps > 10000) {
    throw new Error("invalid commission");
  }
  return Math.floor((amountCents * commissionBps + 5000) / 10000);
}

export function tokensMatch(
  header: string | null,
  expected: string | undefined,
): boolean {
  if (!expected || expected.length < 32 || !header) return false;
  if (header.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < header.length; i++) {
    diff |= header.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

type PaymentProvider = {
  createSubaccount(input: SubaccountInput): Promise<{ walletId: string }>;
  createCustomer(input: CustomerInput): Promise<{ id: string }>;
  createPix(input: PixInput): Promise<PixCreated>;
  authorizeCard(input: CardInput): Promise<{ id: string; status: string }>;
  capture(paymentId: string): Promise<{ id: string; status: string }>;
  refund(paymentId: string): Promise<{ id: string; status: string }>;
  getPayment(paymentId: string): Promise<PaymentView>;
};

export class AsaasProvider implements PaymentProvider {
  constructor(
    private readonly apiKey: string,
    private readonly baseUrl: string,
    private readonly fetchFn: AsaasFetch = fetch,
  ) {
    if (!apiKey) throw new Error("ASAAS_API_KEY ausente");
    if (!baseUrl.startsWith("https://")) {
      throw new Error("ASAAS_BASE_URL inválida");
    }
  }

  static fromEnv(env: {
    get(name: string): string | undefined;
  }): AsaasProvider {
    const apiKey = env.get("ASAAS_API_KEY") ?? "";
    const baseUrl = (env.get("ASAAS_BASE_URL") ?? asaasSandboxBaseUrl)
      .replace(/\/$/, "");
    return new AsaasProvider(apiKey, baseUrl);
  }

  createSubaccount(input: SubaccountInput): Promise<{ walletId: string }> {
    return this.#send("/accounts", input).then((body) => {
      const walletId = stringField(body, "walletId");
      return { walletId };
    });
  }

  createCustomer(input: CustomerInput): Promise<{ id: string }> {
    return this.#send("/customers", input).then((body) => ({
      id: stringField(body, "id"),
    }));
  }

  createPix(input: PixInput): Promise<PixCreated> {
    return this.#send("/payments", {
      customer: input.customer,
      billingType: "PIX",
      value: input.value,
      dueDate: input.dueDate,
      description: input.description,
      externalReference: input.externalReference,
      split: [input.split],
    }).then(async (body) => {
      const id = stringField(body, "id");
      const status = stringField(body, "status");
      const qr = await this.#send(`/payments/${id}/pixQrCode`, undefined, "GET");
      return {
        id,
        status,
        payload: stringField(qr, "payload"),
        encodedImage: stringField(qr, "encodedImage"),
      };
    });
  }

  authorizeCard(input: CardInput): Promise<{ id: string; status: string }> {
    return this.#send("/payments", {
      customer: input.customer,
      billingType: "CREDIT_CARD",
      authorizeOnly: true,
      value: input.value,
      dueDate: input.dueDate,
      description: input.description,
      externalReference: input.externalReference,
      remoteIp: input.remoteIp,
      split: [input.split],
      creditCard: input.creditCard,
      creditCardHolderInfo: input.creditCardHolderInfo,
    }).then((body) => ({
      id: stringField(body, "id"),
      status: stringField(body, "status"),
    }));
  }

  capture(paymentId: string): Promise<{ id: string; status: string }> {
    return this.#send(
      `/payments/${paymentId}/captureAuthorizedPayment`,
      {},
    ).then((body) => ({
      id: stringField(body, "id"),
      status: stringField(body, "status"),
    }));
  }

  refund(paymentId: string): Promise<{ id: string; status: string }> {
    return this.#send(`/payments/${paymentId}/refund`, {}).then((body) => ({
      id: stringField(body, "id"),
      status: stringField(body, "status"),
    }));
  }

  getPayment(paymentId: string): Promise<PaymentView> {
    return this.#send(`/payments/${paymentId}`, undefined, "GET").then(
      (body) => ({
        id: stringField(body, "id"),
        status: stringField(body, "status"),
        billingType: stringField(body, "billingType"),
      }),
    );
  }

  async #send(
    path: string,
    payload: unknown,
    method = "POST",
  ): Promise<Record<string, unknown>> {
    const headers: Record<string, string> = {
      access_token: this.apiKey,
      "User-Agent": "ScapeMatch",
      Accept: "application/json",
    };
    const init: RequestInit = { method, headers };
    if (method !== "GET") {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(payload ?? {});
    }
    const response = await this.fetchFn(`${this.baseUrl}${path}`, init);
    const text = await response.text();
    const safe = text.split(this.apiKey).join("[redacted]");
    if (!response.ok) {
      throw new Error(`Asaas ${response.status}: ${safe.slice(0, 500)}`);
    }
    if (!text) return {};
    return JSON.parse(text) as Record<string, unknown>;
  }
}

function stringField(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Resposta do Asaas sem ${key}`);
  }
  return value;
}
