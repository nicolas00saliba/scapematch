// Gateway Asaas. A chave fica só em Deno.env na função que instancia isto.
// Sandbox: https://api-sandbox.asaas.com/v3
// Produção: https://api.asaas.com/v3
//
// Tokenização: POST /v3/creditCard/tokenizeCreditCard exige access_token.
// Não há SDK de navegador. O cartão só atravessa a chamada de tokenização;
// a cobrança seguinte manda creditCardToken.

import { asaasStatus } from "./asaas_client_error.ts";
import {
  balanceCents,
  findTransferInList,
  parseFinancialTransactions,
  parsePaymentReceivables,
  parseTransfer,
  parseWebhookList,
  transferPayload,
  type WebhookView,
  type FinancialMovement,
  type Receivable,
  type TransferRequest,
  type TransferResult,
} from "./asaas_transfers.ts";
import { localChargeStatus, pixMatchesCharge } from "./pix_charge.ts";
import { redactSensitive } from "./redact.ts";

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
  fixedValue: number;
};

export type PixPaymentRef = {
  id: string;
  status: string;
};

export type PixInput = {
  customer: string;
  value: number;
  dueDate: string;
  description: string;
  externalReference: string;
  split: ChargeSplit;
  /// Segunda linha, só a subconta Reserva de pontos. Vazio no caminho normal.
  extraSplits?: ChargeSplit[];
  /// Chamado assim que o id da cobrança existe, antes do QR.
  onCreated?: (
    payment: PixPaymentRef & { created: boolean },
  ) => Promise<void | string>;
  onCancelFailed?: (paymentId: string) => Promise<void>;
};

/// A linha local já tem outro id. Não sobrescreve o provider_ref.
export class PixReservationLost extends Error {
  readonly paymentId: string;

  constructor(paymentId: string) {
    super("pix_reservation_lost");
    this.name = "PixReservationLost";
    this.paymentId = paymentId;
  }
}

/// O Pix encontrado não confere com customer, valor, split ou status.
export class PixReuseRejected extends Error {
  constructor() {
    super("pix_reuse_mismatch");
    this.name = "PixReuseRejected";
  }
}

/// O QR não veio. A cobrança fica no Asaas para o mesmo externalReference.
export class PixQrUnavailableError extends Error {
  readonly paymentId: string;
  readonly paymentStatus: string;

  constructor(paymentId: string, paymentStatus: string) {
    super("Asaas 502: pix_qr_unavailable");
    this.name = "PixQrUnavailableError";
    this.paymentId = paymentId;
    this.paymentStatus = paymentStatus;
  }
}

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
  remoteIp?: string;
  creditCard: CardSecrets;
  creditCardHolderInfo: CardHolder;
};

export type CardChargeInput = PixInput & {
  remoteIp?: string;
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
  deleted: boolean;
};

/// O Asaas, ao apagar um Pix, pode responder deleted:true e manter
/// status PENDING. Isso é cancelamento confirmado, não cobrança aberta.
export function asaasPaymentGone(body: {
  status?: unknown;
  deleted?: unknown;
}): boolean {
  if (body.deleted === true) return true;
  const status = String(body.status ?? "").trim().toUpperCase();
  return status === "DELETED" || status === "REFUNDED" ||
    status === "CANCELED" || status === "CANCELLED";
}

/// Teto da comissão configurável: 30%. A fórmula ainda usa 10000 como 100%.
const maxConfigurableCommissionBps = 3000;

/// Reais com duas casas, a partir dos centavos inteiros do líquido da casa.
/// A casa continua na primeira linha. Linhas extras entram só quando existem.
export function paymentSplitList(
  house: ChargeSplit,
  extra?: ChargeSplit[] | null,
): ChargeSplit[] {
  const more = (extra ?? []).filter((item) =>
    item.fixedValue > 0 && item.walletId !== house.walletId
  );
  return more.length === 0 ? [house] : [house, ...more];
}

export function fixedReaisFromCents(cents: number): number {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new Error("split");
  }
  return Number((cents / 100).toFixed(2));
}

/// Percentual do bruto que seria da casa. O pagamento usa fixedValue.
export function houseSplitPercent(commissionBps: number): number {
  if (
    !Number.isInteger(commissionBps) || commissionBps < 0 ||
    commissionBps > maxConfigurableCommissionBps
  ) {
    throw new Error("invalid commission");
  }
  return (10000 - commissionBps) / 100;
}

/// Mesma conta de centavos do pacote dominio (meio centavo sobe).
export function commissionCents(
  amountCents: number,
  commissionBps: number,
): number {
  if (
    amountCents < 0 || commissionBps < 0 ||
    commissionBps > maxConfigurableCommissionBps
  ) {
    throw new Error("invalid commission");
  }
  return Math.floor((amountCents * commissionBps + 5000) / 10000);
}

/// Sandbox e produção trocam só a base URL (e a chave). O caminho da nota lê isto.
export function isAsaasSandbox(baseUrl: string): boolean {
  try {
    return new URL(baseUrl).hostname === "api-sandbox.asaas.com";
  } catch {
    return false;
  }
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
  ): Promise<{
    creditCardToken: string;
    creditCardNumber: string;
    creditCardBrand: string;
  }>;
  authorizeCard(
    input: CardChargeInput,
  ): Promise<{ id: string; status: string }>;
  capture(paymentId: string): Promise<{ id: string; status: string }>;
  refund(paymentId: string): Promise<{ id: string; status: string }>;
  cancelAuthorization(
    paymentId: string,
  ): Promise<{ id: string; status: string }>;
  getPayment(paymentId: string): Promise<PaymentView>;
};

const reusablePixStatus = new Set([
  "PENDING",
  "OVERDUE",
  "CONFIRMED",
  "RECEIVED",
  "AUTHORIZED",
]);

/// Cobrança já paga ganha da pendente: reaproveitar a paga evita outro Pix.
export function pickReusablePix(rows: unknown[]): PixPaymentRef | null {
  const pix = rows.filter((row): row is Record<string, unknown> => {
    if (!row || typeof row !== "object") return false;
    const record = row as Record<string, unknown>;
    return record.billingType === "PIX" && typeof record.id === "string" &&
      !asaasPaymentGone(record);
  });
  const settled = pix.find((row) =>
    localChargeStatus(String(row.status ?? "")) === "paid"
  );
  const pending = pix.find((row) =>
    row.status === "PENDING" || row.status === "OVERDUE"
  );
  const chosen = settled ?? pending ??
    pix.find((row) => reusablePixStatus.has(String(row.status)));
  if (!chosen || typeof chosen.id !== "string") return null;
  return {
    id: chosen.id,
    status: typeof chosen.status === "string" ? chosen.status : "",
  };
}

const pixQrAttempts = 3;

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class AsaasProvider implements PaymentProvider {
  constructor(
    private readonly apiKey: string,
    private readonly baseUrl: string,
    private readonly fetchFn: AsaasFetch = fetch,
    private readonly sleep: (ms: number) => Promise<void> = defaultSleep,
  ) {
    if (!apiKey) throw new Error("ASAAS_API_KEY ausente");
    if (!baseUrl.startsWith("https://")) {
      throw new Error("ASAAS_BASE_URL inválida");
    }
  }

  static fromEnv(
    env: { get(name: string): string | undefined },
    timeoutMs = 0,
  ): AsaasProvider {
    const apiKey = env.get("ASAAS_API_KEY") ?? "";
    const baseUrl = (env.get("ASAAS_BASE_URL") ?? asaasSandboxBaseUrl)
      .replace(/\/$/, "");
    const fetchFn: AsaasFetch = timeoutMs > 0
      ? (input, init) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(timeoutMs) })
      : fetch;
    return new AsaasProvider(apiKey, baseUrl, fetchFn);
  }

  get sandbox(): boolean {
    return isAsaasSandbox(this.baseUrl);
  }

  /// Outra chave, a mesma base URL. A subconta emite com a apiKey dela.
  withKey(apiKey: string): AsaasProvider {
    return new AsaasProvider(apiKey, this.baseUrl, this.fetchFn, this.sleep);
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

  scheduleInvoice(
    input: ScheduleInvoiceInput,
  ): Promise<{ id: string; status: string }> {
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

  getCustomer(id: string): Promise<{ id: string; cpfCnpj: string }> {
    return this.#send(`/customers/${id}`, undefined, "GET").then((body) => ({
      id: stringField(body, "id"),
      cpfCnpj: optionalString(body, "cpfCnpj").replace(/\D/g, ""),
    }));
  }

  /// Só o documento. Não manda nome, e-mail nem o corpo antigo.
  updateCustomerCpf(id: string, cpfCnpj: string): Promise<void> {
    return this.#send(`/customers/${id}`, { cpfCnpj }, "PUT").then(
      () => undefined,
    );
  }

  async createPix(input: PixInput): Promise<PixCreated> {
    const payment = await this.#resolvePixPayment(input);
    let active = payment;
    const cancelCreated = async (paymentId: string) => {
      try {
        await this.#deletePayment(paymentId);
      } catch (cancelError) {
        if (asaasStatus(cancelError) === 404) return;
        if (!input.onCancelFailed) throw cancelError;
        await input.onCancelFailed(paymentId);
      }
    };
    try {
      if (input.onCreated) {
        const kept = await input.onCreated(payment);
        if (
          typeof kept === "string" && kept.length > 0 && kept !== payment.id
        ) {
          if (
            payment.created &&
            localChargeStatus(payment.status) !== "paid"
          ) {
            await cancelCreated(payment.id);
          }
          const remote = await this.getPayment(kept);
          active = {
            id: remote.id,
            status: remote.status,
            created: false,
          };
        }
      }
    } catch (error) {
      if (
        payment.created &&
        error instanceof PixReservationLost &&
        localChargeStatus(payment.status) !== "paid"
      ) {
        await cancelCreated(payment.id);
      }
      throw error;
    }
    try {
      const qr = await this.#pixQrWithRetry(active.id);
      return {
        id: active.id,
        status: active.status,
        payload: qr.payload,
        encodedImage: qr.encodedImage,
      };
    } catch (error) {
      if (localChargeStatus(active.status) === "paid") {
        return {
          id: active.id,
          status: active.status,
          payload: "",
          encodedImage: "",
        };
      }
      if (error instanceof PixQrUnavailableError) throw error;
      throw new PixQrUnavailableError(payment.id, payment.status);
    }
  }

  async getPixQrCode(
    paymentId: string,
  ): Promise<{ payload: string; encodedImage: string }> {
    try {
      return await this.#pixQrWithRetry(paymentId);
    } catch (error) {
      if (error instanceof PixQrUnavailableError) throw error;
      throw new PixQrUnavailableError(paymentId, "PENDING");
    }
  }

  async #resolvePixPayment(
    input: PixInput,
  ): Promise<PixPaymentRef & { created: boolean }> {
    const reference = input.externalReference.trim();
    if (!reference) throw new Error("externalReference ausente");
    const existing = await this.#findReusablePix(reference);
    if (existing) {
      const full = await this.#send(
        `/payments/${existing.id}`,
        undefined,
        "GET",
      );
      if (
        !pixMatchesCharge(full, {
          customer: input.customer,
          valueCents: Math.round(input.value * 100),
          walletId: input.split.walletId,
          fixedValue: input.split.fixedValue,
        })
      ) {
        throw new PixReuseRejected();
      }
      return {
        id: stringField(full, "id"),
        status: stringField(full, "status"),
        created: false,
      };
    }
    const body = await this.#send("/payments", {
      customer: input.customer,
      billingType: "PIX",
      value: input.value,
      dueDate: input.dueDate,
      description: input.description,
      externalReference: reference,
      split: paymentSplitList(input.split, input.extraSplits),
    });
    return {
      id: stringField(body, "id"),
      status: stringField(body, "status"),
      created: true,
    };
  }

  #deletePayment(paymentId: string): Promise<void> {
    return this.#send(`/payments/${paymentId}`, undefined, "DELETE").then(
      () => undefined,
    );
  }

  findPix(reference: string): Promise<PixPaymentRef | null> {
    return this.#findReusablePix(reference);
  }

  /// Qualquer cobrança ainda viva com esse externalReference.
  async findByExternalReference(
    reference: string,
  ): Promise<PaymentView | null> {
    const query = new URLSearchParams({
      externalReference: reference,
      limit: "20",
    });
    const body = await this.#send(`/payments?${query}`, undefined, "GET");
    const rows = Array.isArray(body.data) ? body.data : [];
    const live = rows.filter((row): row is Record<string, unknown> => {
      if (!row || typeof row !== "object") return false;
      const record = row as Record<string, unknown>;
      if (typeof record.id !== "string" || record.id.length === 0) return false;
      return !asaasPaymentGone(record);
    });
    const chosen = live[0];
    if (!chosen || typeof chosen.id !== "string") return null;
    return {
      id: chosen.id,
      status: typeof chosen.status === "string" ? chosen.status : "",
      billingType: typeof chosen.billingType === "string"
        ? chosen.billingType
        : "",
      deleted: false,
    };
  }

  /// DELETE e confirma que o Pix não segue aberto.
  /// deleted:true com status PENDING conta como cancelado.
  async cancelPaymentConfirmed(paymentId: string): Promise<boolean> {
    try {
      const body = await this.#send(
        `/payments/${paymentId}`,
        undefined,
        "DELETE",
      );
      if (asaasPaymentGone(body)) return true;
    } catch (error) {
      if (asaasStatus(error) === 404) return true;
      return false;
    }
    try {
      const remote = await this.readPayment(paymentId);
      return asaasPaymentGone(remote);
    } catch (error) {
      return asaasStatus(error) === 404;
    }
  }

  async #findReusablePix(reference: string): Promise<PixPaymentRef | null> {
    const query = new URLSearchParams({
      externalReference: reference,
      limit: "20",
    });
    const body = await this.#send(`/payments?${query}`, undefined, "GET");
    const rows = Array.isArray(body.data) ? body.data : [];
    return pickReusablePix(rows);
  }

  async #pixQrWithRetry(
    paymentId: string,
  ): Promise<{ payload: string; encodedImage: string }> {
    let last: unknown;
    for (let attempt = 0; attempt < pixQrAttempts; attempt++) {
      if (attempt > 0) await this.sleep(100 * attempt);
      try {
        return await this.#readPixQr(paymentId);
      } catch (error) {
        last = error;
      }
    }
    throw last instanceof Error
      ? last
      : new PixQrUnavailableError(paymentId, "PENDING");
  }

  #readPixQr(
    paymentId: string,
  ): Promise<{ payload: string; encodedImage: string }> {
    return this.#send(`/payments/${paymentId}/pixQrCode`, undefined, "GET")
      .then((qr) => ({
        payload: stringField(qr, "payload"),
        encodedImage: stringField(qr, "encodedImage"),
      }));
  }

  tokenizeCard(input: TokenizeInput): Promise<{
    creditCardToken: string;
    creditCardNumber: string;
    creditCardBrand: string;
  }> {
    const payload: Record<string, unknown> = {
      customer: input.customer,
      creditCard: input.creditCard,
      creditCardHolderInfo: input.creditCardHolderInfo,
    };
    if (input.remoteIp) payload.remoteIp = input.remoteIp;
    return this.#send("/creditCard/tokenizeCreditCard", payload).then((
      body,
    ) => ({
      creditCardToken: stringField(body, "creditCardToken"),
      creditCardNumber: optionalString(body, "creditCardNumber"),
      creditCardBrand: optionalString(body, "creditCardBrand"),
    }));
  }

  authorizeCard(
    input: CardChargeInput,
  ): Promise<{ id: string; status: string }> {
    const payload: Record<string, unknown> = {
      customer: input.customer,
      billingType: "CREDIT_CARD",
      authorizeOnly: true,
      value: input.value,
      dueDate: input.dueDate,
      description: input.description,
      externalReference: input.externalReference,
      split: paymentSplitList(input.split, input.extraSplits),
      creditCardToken: input.creditCardToken,
    };
    if (input.remoteIp) payload.remoteIp = input.remoteIp;
    return this.#send("/payments", payload).then((body) => ({
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

  /// Solta a pré-autorização do cartão com estorno, como a API do Asaas
  /// documenta. Pix pendente continua no DELETE de cancelPaymentConfirmed.
  cancelAuthorization(
    paymentId: string,
  ): Promise<{ id: string; status: string }> {
    return this.#send(`/payments/${paymentId}/refund`, {}).then((body) => ({
      id: typeof body.id === "string" && body.id.length > 0
        ? body.id
        : paymentId,
      status: typeof body.status === "string" && body.status.length > 0
        ? body.status
        : "REFUNDED",
    }));
  }

  financeBalanceCents(): Promise<number> {
    return this.#send("/finance/balance", undefined, "GET").then(balanceCents);
  }

  confirmedReceivables(): Promise<Receivable[]> {
    return this.#send(
      "/payments?status=CONFIRMED&limit=100",
      undefined,
      "GET",
    ).then(parsePaymentReceivables);
  }

  financialTransactions(): Promise<FinancialMovement[]> {
    return this.#send(
      "/financialTransactions?limit=100",
      undefined,
      "GET",
    ).then(parseFinancialTransactions);
  }

  createTransfer(input: TransferRequest): Promise<TransferResult> {
    return this.#send("/transfers", transferPayload(input)).then(parseTransfer);
  }

  findTransfer(externalReference: string): Promise<TransferResult | null> {
    const query = encodeURIComponent(externalReference);
    return this.#send(
      `/transfers?externalReference=${query}&limit=10`,
      undefined,
      "GET",
    ).then((body) => findTransferInList(body, externalReference));
  }

  readTransfer(id: string): Promise<TransferResult> {
    if (!/^[A-Za-z0-9_-]{4,64}$/.test(id)) throw new Error("valor");
    return this.#send(
      `/transfers/${encodeURIComponent(id)}`,
      undefined,
      "GET",
    ).then(parseTransfer);
  }

  /// Webhooks da conta desta apiKey. Na subconta, a chave tem de ser a dela.
  listWebhooks(): Promise<WebhookView[]> {
    return this.#send("/webhooks?limit=100", undefined, "GET").then(
      parseWebhookList,
    );
  }

  saveWebhook(body: Record<string, unknown>, id?: string): Promise<void> {
    if (id !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
      throw new Error("valor");
    }
    const path = id ? `/webhooks/${encodeURIComponent(id)}` : "/webhooks";
    return this.#send(path, body, id ? "PUT" : "POST").then(() => undefined);
  }

  readPayment(paymentId: string): Promise<Record<string, unknown>> {
    return this.#send(`/payments/${paymentId}`, undefined, "GET");
  }

  /// O webhook da cobrança não traz o CPF. O id vem em pixTransaction.
  getPixTransaction(id: string): Promise<Record<string, unknown>> {
    return this.#send(`/pix/transactions/${id}`, undefined, "GET");
  }

  getPayment(paymentId: string): Promise<PaymentView> {
    return this.#send(`/payments/${paymentId}`, undefined, "GET").then(
      (body) => ({
        id: stringField(body, "id"),
        status: stringField(body, "status"),
        billingType: stringField(body, "billingType"),
        deleted: body.deleted === true,
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
      "User-Agent": "EscapeMatch",
      Accept: "application/json",
    };
    const init: RequestInit = { method, headers };
    if (method !== "GET") {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(payload ?? {});
    }
    const response = await this.fetchFn(`${this.baseUrl}${path}`, init);
    const text = await response.text();
    const safe = redactOutbound(text, this.apiKey);
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

function redactOutbound(text: string, apiKey: string): string {
  const withoutKey = apiKey ? text.split(apiKey).join("[redacted]") : text;
  return redactSensitive(withoutKey);
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
