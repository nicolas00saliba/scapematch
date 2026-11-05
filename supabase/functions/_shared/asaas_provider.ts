// Gateway Asaas. A chave fica só em Deno.env na função que instancia isto.
// Sandbox: https://api-sandbox.asaas.com/v3
// Produção: https://api.asaas.com/v3
//
// Tokenização: POST /v3/creditCard/tokenizeCreditCard exige access_token.
// Não há SDK de navegador. O cartão só atravessa a chamada de tokenização;
// a cobrança seguinte manda creditCardToken.

import { redactSensitive, sensitiveStrings } from "./redact.ts";

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

export type CardSecrets = {
  holderName: string;
  number: string;
  expiryMonth: string;
  expiryYear: string;
  ccv: string;
};

export type CardHolder = {
  name: string;
  email: string;
  cpfCnpj: string;
  postalCode: string;
  addressNumber: string;
  phone: string;
};

export type TokenizeInput = {
  customer: string;
  remoteIp: string;
  creditCard: CardSecrets;
  creditCardHolderInfo: CardHolder;
};

export type CardChargeInput = PixInput & {
  remoteIp: string;
  creditCardToken: string;
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

/// Sandbox e produção trocam só a base URL (e a chave). O caminho da nota lê isto.
export function isAsaasSandbox(baseUrl: string): boolean {
  return baseUrl.includes("://api-sandbox.asaas.com");
}

export function centsToReais(cents: number): number {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new Error("invalid cents");
  }
  return cents / 100;
}

export type FiscalInfoInput = {
  email: string;
  municipalInscription: string;
  simplesNacional: boolean;
  cnae?: string;
  rpsSerie?: string;
  rpsNumber?: number;
  serviceListItem?: string;
  username?: string;
  password?: string;
};

export type InvoiceTaxes = {
  retainIss: boolean;
  iss: number;
  cofins: number;
  csll: number;
  inss: number;
  ir: number;
  pis: number;
};

export type ScheduleInvoiceInput = {
  customer: string;
  serviceDescription: string;
  observations?: string;
  value: number;
  deductions: number;
  effectiveDate: string;
  municipalServiceCode: string;
  municipalServiceName: string;
  externalReference: string;
  taxes: InvoiceTaxes;
};

export type InvoiceView = {
  id: string;
  status: string;
  number: string;
  pdfUrl: string;
  xmlUrl: string;
};

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
  createSubaccount(
    input: SubaccountInput,
  ): Promise<{ walletId: string; apiKey: string }>;
  createCustomer(input: CustomerInput): Promise<{ id: string }>;
  createPix(input: PixInput): Promise<PixCreated>;
  tokenizeCard(
    input: TokenizeInput,
  ): Promise<{ creditCardToken: string }>;
  authorizeCard(input: CardChargeInput): Promise<{ id: string; status: string }>;
  capture(paymentId: string): Promise<{ id: string; status: string }>;
  refund(paymentId: string): Promise<{ id: string; status: string }>;
  cancelAuthorization(paymentId: string): Promise<{ id: string; status: string }>;
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

  get sandbox(): boolean {
    return isAsaasSandbox(this.baseUrl);
  }

  /// Outra chave, a mesma base URL. A subconta emite com a apiKey dela.
  withKey(apiKey: string): AsaasProvider {
    return new AsaasProvider(apiKey, this.baseUrl, this.fetchFn);
  }

  createSubaccount(
    input: SubaccountInput,
  ): Promise<{ walletId: string; apiKey: string }> {
    return this.#send("/accounts", input).then((body) => {
      const walletId = stringField(body, "walletId");
      const apiKey = stringField(body, "apiKey");
      return { walletId, apiKey };
    });
  }

  configureFiscalInfo(input: FiscalInfoInput): Promise<void> {
    const body: Record<string, unknown> = {
      email: input.email,
      municipalInscription: input.municipalInscription,
      simplesNacional: input.simplesNacional,
    };
    if (input.cnae) body.cnae = input.cnae;
    if (input.rpsSerie) body.rpsSerie = input.rpsSerie;
    if (input.rpsNumber != null) body.rpsNumber = input.rpsNumber;
    if (input.serviceListItem) body.serviceListItem = input.serviceListItem;
    if (input.username) body.username = input.username;
    if (input.password) body.password = input.password;
    return this.#send("/fiscalInfo", body).then(() => undefined);
  }

  scheduleInvoice(input: ScheduleInvoiceInput): Promise<{ id: string; status: string }> {
    return this.#send("/invoices", {
      customer: input.customer,
      serviceDescription: input.serviceDescription,
      observations: input.observations ?? "",
      value: input.value,
      deductions: input.deductions,
      effectiveDate: input.effectiveDate,
      municipalServiceCode: input.municipalServiceCode,
      municipalServiceName: input.municipalServiceName,
      externalReference: input.externalReference,
      taxes: input.taxes,
    }).then((body) => ({
      id: stringField(body, "id"),
      status: stringField(body, "status"),
    }));
  }

  authorizeInvoice(invoiceId: string): Promise<{ id: string; status: string }> {
    return this.#send(`/invoices/${invoiceId}/authorize`, {}).then((body) => ({
      id: stringField(body, "id"),
      status: optionalString(body, "status"),
    }));
  }

  getInvoice(invoiceId: string): Promise<InvoiceView> {
    return this.#send(`/invoices/${invoiceId}`, undefined, "GET").then(
      (body) => ({
        id: stringField(body, "id"),
        status: stringField(body, "status"),
        number: optionalString(body, "number"),
        pdfUrl: optionalString(body, "pdfUrl"),
        xmlUrl: optionalString(body, "xmlUrl"),
      }),
    );
  }

  cancelInvoice(invoiceId: string): Promise<{ id: string; status: string }> {
    return this.#send(`/invoices/${invoiceId}/cancel`, {}).then((body) => ({
      id: stringField(body, "id"),
      status: optionalString(body, "status"),
    }));
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

  tokenizeCard(input: TokenizeInput): Promise<{ creditCardToken: string }> {
    return this.#send("/creditCard/tokenizeCreditCard", {
      customer: input.customer,
      creditCard: input.creditCard,
      creditCardHolderInfo: input.creditCardHolderInfo,
      remoteIp: input.remoteIp,
    }).then((body) => ({
      creditCardToken: stringField(body, "creditCardToken"),
    }));
  }

  authorizeCard(input: CardChargeInput): Promise<{ id: string; status: string }> {
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
      creditCardToken: input.creditCardToken,
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

  /// Cancela uma autorização de cartão que ainda não foi capturada.
  cancelAuthorization(
    paymentId: string,
  ): Promise<{ id: string; status: string }> {
    return this.#send(`/payments/${paymentId}`, undefined, "DELETE").then(
      (body) => ({
        id: typeof body.id === "string" && body.id.length > 0
          ? body.id
          : paymentId,
        status: typeof body.status === "string" && body.status.length > 0
          ? body.status
          : "DELETED",
      }),
    );
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
    const safe = redactOutbound(text, this.apiKey, payload);
    if (!response.ok) {
      throw new Error(`Asaas ${response.status}: ${safe.slice(0, 500)}`);
    }
    if (!text) return {};
    try {
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new Error("Resposta do Asaas inválida");
    }
  }
}

/// Na primeira vez o cartão só vai para a tokenização. A cobrança usa o token.
/// Com token já emitido, o cartão nem é lido de novo.
export async function authorizeStoredCard(
  provider: AsaasProvider,
  input: {
    charge: Omit<CardChargeInput, "creditCardToken">;
    creditCardToken?: string;
    creditCard?: CardSecrets;
    creditCardHolderInfo?: CardHolder;
  },
): Promise<{ id: string; status: string; creditCardToken: string }> {
  const supplied = input.creditCardToken?.trim() ?? "";
  const creditCardToken = supplied.length > 0
    ? supplied
    : (await provider.tokenizeCard({
      customer: input.charge.customer,
      remoteIp: input.charge.remoteIp,
      creditCard: requireCard(input.creditCard),
      creditCardHolderInfo: requireHolder(input.creditCardHolderInfo),
    })).creditCardToken;
  const authorized = await provider.authorizeCard({
    ...input.charge,
    creditCardToken,
  });
  return { ...authorized, creditCardToken };
}

function requireCard(card: CardSecrets | undefined): CardSecrets {
  if (
    !card?.number || !card.ccv || !card.holderName || !card.expiryMonth ||
    !card.expiryYear
  ) {
    throw new Error("Dados do cartão incompletos.");
  }
  return card;
}

function requireHolder(holder: CardHolder | undefined): CardHolder {
  if (!holder) throw new Error("Dados do cartão incompletos.");
  return holder;
}

function redactOutbound(text: string, apiKey: string, payload: unknown): string {
  const withoutKey = apiKey ? text.split(apiKey).join("[redacted]") : text;
  const secrets = sensitiveStrings(payload);
  if (secrets.length === 0) return withoutKey;
  return redactSensitive(withoutKey, secrets);
}

function stringField(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Resposta do Asaas sem ${key}`);
  }
  return value;
}

function optionalString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value === "number") return String(value);
  if (typeof value !== "string") return "";
  return value;
}
