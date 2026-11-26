// Gateway PagBank em produção por padrão.
// Produção: https://api.pagseguro.com
// Sandbox só com PAGBANK_ENV=sandbox.
// A chave fica só em Deno.env. O cartão cru não entra em log.

import { providerStatus } from "./pagbank_client_error.ts";
import {
  buyerInterestFromQuote,
  chargeAmountBody,
  fixedSplit,
  installmentCharge,
  installmentMenu,
  interestFreeInstallments,
  maxInstallments,
  pagbankSplitBody,
  type FixedSplit,
  type InstallmentCharge,
  type InstallmentOption,
} from "./pagbank_rules.ts";
import { localChargeStatus, pixMatchesCharge } from "./pix_charge.ts";
import { redactSensitive } from "./redact.ts";
import {
  findTransferInList,
  parseTransfer,
  parseWebhookList,
  readAccountBalance,
  transferPayload,
  type TransferRequest,
  type TransferResult,
  type WebhookView,
} from "./pagbank_transfers.ts";
export { commissionCents } from "./pagbank_rules.ts";
export { centsToReais } from "./pagbank_transfers.ts";

export type ScheduleInvoiceInput = {
  customer: string;
  serviceDescription: string;
  observations: string;
  value: number;
  deductions: number;
  effectiveDate: string;
  municipalServiceCode: string;
  municipalServiceName: string;
  externalReference: string;
  taxes: Record<string, number | boolean>;
};

export const pagbankSandboxBaseUrl = "https://sandbox.api.pagseguro.com";
export const pagbankProductionBaseUrl = "https://api.pagseguro.com";
export const pagbankConnectAuthorizeUrl =
  "https://connect.pagbank.com.br/oauth2/authorize";
export const pagbankConnectSandboxAuthorizeUrl =
  "https://connect.sandbox.pagbank.com.br/oauth2/authorize";

export type PagBankFetch = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export type ChargeSplit = {
  walletId: string;
  fixedValue: number;
};

export type PixPaymentRef = {
  id: string;
  status: string;
  splitId?: string;
};

export type CustomerDetails = {
  name: string;
  email: string;
  taxId: string;
};

export type PixInput = {
  customer: string;
  value: number;
  dueDate: string;
  description: string;
  externalReference: string;
  split: ChargeSplit;
  extraSplits?: ChargeSplit[];
  customerDetails?: CustomerDetails;
  onCreated?: (
    payment: PixPaymentRef & { created: boolean },
  ) => Promise<void | string>;
  onCancelFailed?: (paymentId: string) => Promise<void>;
};

export class PixReservationLost extends Error {
  readonly paymentId: string;

  constructor(paymentId: string) {
    super("pix_reservation_lost");
    this.name = "PixReservationLost";
    this.paymentId = paymentId;
  }
}

export class PixReuseRejected extends Error {
  constructor() {
    super("pix_reuse_mismatch");
    this.name = "PixReuseRejected";
  }
}

export class PixQrUnavailableError extends Error {
  readonly paymentId: string;
  readonly paymentStatus: string;

  constructor(paymentId: string, paymentStatus: string) {
    super("PagBank 502: pix_qr_unavailable");
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
  installments?: number;
  buyerInterestCents?: number;
};

export type PixCreated = {
  id: string;
  status: string;
  payload: string;
  encodedImage: string;
  splitId: string;
};

export type PaymentView = {
  id: string;
  status: string;
  billingType: string;
  deleted: boolean;
  splitId: string;
  /// ISO da doc (`payment_method.pix.expiration_date`). Vazio se não houver.
  expiresAt: string;
};

export type CustomerInput = {
  name: string;
  email: string;
  externalReference: string;
  cpfCnpj?: string;
};

export function providerPaymentGone(body: {
  status?: unknown;
  deleted?: unknown;
}): boolean {
  if (body.deleted === true) return true;
  const status = String(body.status ?? "").trim().toUpperCase();
  return status === "DELETED" || status === "REFUNDED" ||
    status === "CANCELED" || status === "CANCELLED" || status === "DECLINED";
}

export function fixedReaisFromCents(cents: number): number {
  if (!Number.isInteger(cents) || cents < 0) throw new Error("split");
  return Number((cents / 100).toFixed(2));
}

export function isPagBankSandbox(baseUrl: string): boolean {
  try {
    return new URL(baseUrl).hostname === "sandbox.api.pagseguro.com";
  } catch {
    return false;
  }
}

export function isOfficialPagBankBase(baseUrl: string): boolean {
  const base = baseUrl.trim().replace(/\/$/, "");
  return base === pagbankSandboxBaseUrl || base === pagbankProductionBaseUrl;
}

export function pagbankBaseUrlIsProduction(baseUrl: string): boolean {
  return baseUrl.trim().replace(/\/$/, "") === pagbankProductionBaseUrl;
}

/// Produção é o padrão. Sandbox só com PAGBANK_ENV=sandbox.
/// PAGBANK_BASE_URL não escolhe o host.
/// A doc de Pedidos (POST /orders) manda `notification_urls` como array de URL.
export function pagbankOrderNotificationUrl(
  env: { get(name: string): string | undefined },
): string {
  const base = (env.get("SUPABASE_URL") ?? "").trim().replace(/\/$/, "");
  if (!base.startsWith("https://")) return "";
  return `${base}/functions/v1/pagbank-webhook`;
}

export function pagbankApiBaseUrl(
  env: { get(name: string): string | undefined },
): string {
  const mode = (env.get("PAGBANK_ENV") ?? "production").trim().toLowerCase();
  return mode === "sandbox" ? pagbankSandboxBaseUrl : pagbankProductionBaseUrl;
}

/// SHA-256 hex de `{segredo}-{corpo cru}`. O corpo não pode ser reformatado.
export async function pagbankAuthenticityToken(
  secret: string,
  rawBody: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${secret}-${rawBody}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function pagbankSignatureMatches(
  header: string | null,
  secret: string | undefined,
  rawBody: string,
): Promise<boolean> {
  if (!secret || secret.length < 16 || !header) return false;
  const expected = await pagbankAuthenticityToken(secret, rawBody);
  const received = header.trim().toLowerCase();
  if (expected.length !== received.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ received.charCodeAt(i);
  }
  return diff === 0;
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

const reusableStatus = new Set([
  "PENDING",
  "OVERDUE",
  "CONFIRMED",
  "RECEIVED",
  "AUTHORIZED",
]);

export function pickReusablePix(rows: unknown[]): PixPaymentRef | null {
  const pix = rows.filter((row): row is Record<string, unknown> => {
    if (!row || typeof row !== "object") return false;
    const record = row as Record<string, unknown>;
    return record.billingType === "PIX" && typeof record.id === "string" &&
      !providerPaymentGone(record);
  });
  const settled = pix.find((row) =>
    localChargeStatus(String(row.status ?? "")) === "paid"
  );
  const pending = pix.find((row) =>
    row.status === "PENDING" || row.status === "OVERDUE"
  );
  const chosen = settled ?? pending ??
    pix.find((row) => reusableStatus.has(String(row.status)));
  if (!chosen || typeof chosen.id !== "string") return null;
  const orderId = typeof chosen.orderId === "string" ? chosen.orderId : "";
  return {
    id: orderId.startsWith("ORDE_") ? orderId : chosen.id,
    status: typeof chosen.status === "string" ? chosen.status : "",
    splitId: typeof chosen.splitId === "string" ? chosen.splitId : "",
  };
}

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function warnBalanceShape(): void {
  console.error(JSON.stringify({
    scope: "pagbank-balance",
    code: "balance_shape",
  }));
}

export class PagBankProvider {
  readonly sandbox: boolean;
  readonly official: boolean;
  #refreshAccess: (() => Promise<string>) | null = null;

  constructor(
    private apiKey: string,
    private readonly baseUrl: string,
    private readonly fetchFn: PagBankFetch = fetch,
    private readonly sleep: (ms: number) => Promise<void> = defaultSleep,
    private readonly primaryAccountId = "",
    private readonly notificationUrl = "",
  ) {
    if (!apiKey) throw new Error("PAGBANK_TOKEN ausente");
    if (!baseUrl.startsWith("https://")) {
      throw new Error("PAGBANK_BASE_URL inválida");
    }
    this.sandbox = isPagBankSandbox(baseUrl);
    this.official = isOfficialPagBankBase(baseUrl);
  }

  static fromEnv(
    env: { get(name: string): string | undefined },
    timeoutMs = 0,
    fetchImpl?: PagBankFetch,
  ): PagBankProvider {
    const apiKey = env.get("PAGBANK_TOKEN") ?? "";
    const baseUrl = pagbankApiBaseUrl(env);
    const account = env.get("PAGBANK_ACCOUNT_ID") ?? "";
    const baseFetch = fetchImpl ?? fetch;
    const fetchFn: PagBankFetch = timeoutMs > 0
      ? (input, init) =>
        baseFetch(input, { ...init, signal: AbortSignal.timeout(timeoutMs) })
      : baseFetch;
    return new PagBankProvider(
      apiKey,
      baseUrl,
      fetchFn,
      defaultSleep,
      account,
      pagbankOrderNotificationUrl(env),
    );
  }

  /// Na resposta 401, troca o access token uma vez e repete a chamada.
  bindAccessRefresh(refresh: () => Promise<string>): void {
    this.#refreshAccess = refresh;
  }

  withKey(apiKey: string): PagBankProvider {
    return new PagBankProvider(
      apiKey,
      this.baseUrl,
      this.fetchFn,
      this.sleep,
      this.primaryAccountId,
      this.notificationUrl,
    );
  }

  connectAuthorizeUrl(input: {
    clientId: string;
    redirectUri: string;
    state: string;
  }): string {
    const base = this.sandbox
      ? pagbankConnectSandboxAuthorizeUrl
      : pagbankConnectAuthorizeUrl;
    const query = new URLSearchParams({
      response_type: "code",
      client_id: input.clientId,
      redirect_uri: input.redirectUri,
      scope: "payments.read payments.create payments.refund accounts.read",
      state: input.state,
    });
    return `${base}?${query}`;
  }

  exchangeConnectCode(input: {
    clientId: string;
    clientSecret: string;
    code: string;
    redirectUri: string;
  }): Promise<{
    accessToken: string;
    refreshToken: string;
    expiresIn: number;
    accountId: string;
  }> {
    return this.#send(
      "/oauth2/token",
      {
        grant_type: "authorization_code",
        code: input.code,
        redirect_uri: input.redirectUri,
      },
      "POST",
      {
        X_CLIENT_ID: input.clientId,
        X_CLIENT_SECRET: input.clientSecret,
      },
    ).then((body) => ({
      accessToken: stringField(body, "access_token"),
      refreshToken: optionalString(body, "refresh_token"),
      expiresIn: expiresInSeconds(body),
      accountId: stringField(body, "account_id"),
    }));
  }

  /// Revoga um token do Connect no PagBank (POST /oauth2/revoke). O
  /// Authorization leva o token de acesso da casa; X_CLIENT_* identificam o
  /// app. Lança se o PagBank recusar: quem chama decide se isso para o fluxo.
  async revokeConnectToken(input: {
    clientId: string;
    clientSecret: string;
    bearerToken: string;
    token: string;
    hint: "access_token" | "refresh_token";
  }): Promise<void> {
    await this.#send(
      "/oauth2/revoke",
      { token_type_hint: input.hint, token: input.token },
      "POST",
      {
        Authorization: `Bearer ${input.bearerToken}`,
        X_CLIENT_ID: input.clientId,
        X_CLIENT_SECRET: input.clientSecret,
      },
      false,
    );
  }

  refreshConnectToken(input: {
    clientId: string;
    clientSecret: string;
    refreshToken: string;
  }): Promise<{
    accessToken: string;
    refreshToken: string;
    expiresIn: number;
    accountId: string;
  }> {
    return this.#send(
      "/oauth2/token",
      {
        grant_type: "refresh_token",
        refresh_token: input.refreshToken,
      },
      "POST",
      {
        X_CLIENT_ID: input.clientId,
        X_CLIENT_SECRET: input.clientSecret,
      },
    ).then((body) => ({
      accessToken: stringField(body, "access_token"),
      refreshToken: optionalString(body, "refresh_token") || input.refreshToken,
      expiresIn: expiresInSeconds(body),
      accountId: optionalString(body, "account_id"),
    }));
  }

  /// Cliente da PagBank vai no pedido. O id local não é uma chamada de rede.
  createCustomer(input: CustomerInput): Promise<{ id: string }> {
    const ref = input.externalReference.trim();
    if (!ref) return Promise.reject(new Error("customer"));
    return Promise.resolve({ id: `PB_CUS_${ref}` });
  }

  getCustomer(
    id: string,
  ): Promise<{ id: string; cpfCnpj: string; deleted: boolean }> {
    const kept = id.startsWith("PB_CUS_");
    return Promise.resolve({
      id,
      cpfCnpj: "",
      deleted: !kept,
    });
  }

  deleteCustomer(_id: string): Promise<void> {
    return Promise.resolve();
  }

  updateCustomerCpf(_id: string, _cpfCnpj: string): Promise<void> {
    return Promise.resolve();
  }

  async createPix(input: PixInput): Promise<PixCreated> {
    const payment = await this.#resolvePixPayment(input);
    let active = payment;
    const cancelCreated = async (paymentId: string) => {
      try {
        await this.#cancelCharge(paymentId);
      } catch (cancelError) {
        if (providerStatus(cancelError) === 404) return;
        if (!input.onCancelFailed) throw cancelError;
        await input.onCancelFailed(paymentId);
      }
    };
    try {
      if (input.onCreated) {
        const kept = await input.onCreated(payment);
        if (typeof kept === "string" && kept.length > 0 && kept !== payment.id) {
          if (payment.created && localChargeStatus(payment.status) !== "paid") {
            await cancelCreated(payment.id);
          }
          const remote = await this.getPayment(kept);
          active = {
            id: remote.id,
            status: remote.status,
            splitId: remote.splitId,
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
    if (localChargeStatus(active.status) === "paid") {
      return {
        id: active.id,
        status: active.status,
        payload: "",
        encodedImage: "",
        splitId: active.splitId ?? "",
      };
    }
    try {
      const qr = active.qr ?? await this.#pixQrWithRetry(active.id);
      return {
        id: active.id,
        status: active.status,
        payload: qr.payload,
        encodedImage: qr.encodedImage,
        splitId: active.splitId ?? "",
      };
    } catch (error) {
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

  findPix(reference: string): Promise<PixPaymentRef | null> {
    return this.#findReusablePix(reference);
  }

  async findByExternalReference(
    reference: string,
  ): Promise<PaymentView | null> {
    const rows = await this.#ordersByReference(reference);
    const live = rows.filter((row) => !providerPaymentGone(row));
    const chosen = live[0];
    if (!chosen) return null;
    const orderId = typeof chosen.orderId === "string" ? chosen.orderId : "";
    return {
      id: orderId.startsWith("ORDE_") ? orderId : String(chosen.id),
      status: String(chosen.status ?? ""),
      billingType: String(chosen.billingType ?? ""),
      deleted: false,
      splitId: String(chosen.splitId ?? ""),
      expiresAt: "",
    };
  }

  async cancelPaymentConfirmed(paymentId: string): Promise<boolean> {
    try {
      const body = await this.#cancelCharge(paymentId);
      if (providerPaymentGone(normalizeCharge(body))) return true;
    } catch (error) {
      if (providerStatus(error) === 404) return true;
      return false;
    }
    try {
      const remote = await this.readPayment(paymentId);
      return providerPaymentGone(normalizeCharge(remote));
    } catch (error) {
      return providerStatus(error) === 404;
    }
  }

  tokenizeCard(input: TokenizeInput): Promise<{
    creditCardToken: string;
    creditCardNumber: string;
    creditCardBrand: string;
  }> {
    const card = input.creditCard;
    return this.#send("/tokens/cards", {
      number: card.number,
      exp_month: card.expiryMonth,
      exp_year: card.expiryYear,
      security_code: card.ccv,
      holder: {
        name: input.creditCardHolderInfo.name || card.holderName,
        tax_id: input.creditCardHolderInfo.cpfCnpj,
      },
    }).then((body) => ({
      creditCardToken: stringField(body, "id"),
      creditCardNumber: optionalString(body, "last_digits"),
      creditCardBrand: optionalString(body, "brand"),
    }));
  }

  async authorizeCard(
    input: CardChargeInput,
  ): Promise<{ id: string; status: string; splitId: string }> {
    const order = await this.#createOrder(input, "CREDIT_CARD");
    const charge = firstCharge(order);
    const status = mapStatus(stringField(charge, "status"), charge);
    if (status === "CANCELED") {
      throw new Error(
        'PagBank 400: {"errors":[{"code":"invalid_creditCard","description":"recusado"}]}',
      );
    }
    return {
      id: stringField(charge, "id"),
      status,
      splitId: splitIdOf(charge),
    };
  }

  capture(
    paymentId: string,
    amountCents = 0,
  ): Promise<{ id: string; status: string }> {
    return this.#chargeMoney(paymentId, amountCents).then((target) =>
      this.#send(
        `/charges/${encodeURIComponent(target.chargeId)}/capture`,
        { amount: { value: target.value } },
      ).then((body) => ({
        id: optionalString(body, "id") || target.chargeId,
        status: mapStatus(optionalString(body, "status") || "PAID", body),
      }))
    );
  }

  refund(
    paymentId: string,
    amountCents = 0,
  ): Promise<{ id: string; status: string }> {
    return this.#cancelCharge(paymentId, amountCents).then((body) => ({
      id: optionalString(body, "id") || paymentId,
      status: "REFUNDED",
    }));
  }

  cancelAuthorization(
    paymentId: string,
    amountCents = 0,
  ): Promise<{ id: string; status: string }> {
    return this.#cancelCharge(paymentId, amountCents).then((body) => ({
      id: optionalString(body, "id") || paymentId,
      status: "CANCELED",
    }));
  }

  /// Solta a custódia HELD depois que a sessão começou.
  releaseCustody(
    splitId: string,
    accountIds: string[],
  ): Promise<void> {
    const id = splitId.trim();
    if (!id) return Promise.resolve();
    const receivers = accountIds
      .map((item) => item.trim())
      .filter((item, index, all) => item.length > 0 && all.indexOf(item) === index)
      .map((accountId) => ({ account: { id: accountId } }));
    if (receivers.length === 0) {
      return Promise.reject(new Error("custodia_recebedores"));
    }
    return this.#send(
      `/splits/${encodeURIComponent(id)}/custody/release`,
      { receivers },
    ).then(() => undefined);
  }

  /// Conta primária da EscapeMatch. Entra na liberação da custódia.
  accountId(): string {
    return this.#primary();
  }

  async quoteBuyerInterest(
    principalCents: number,
    installments: number,
  ): Promise<number> {
    if (installments > maxInstallments) throw new Error("parcelas");
    if (installments <= interestFreeInstallments) return 0;
    const query = new URLSearchParams({
      payment_methods: "CREDIT_CARD",
      value: String(principalCents),
      max_installments: String(maxInstallments),
      max_installments_no_interest: String(interestFreeInstallments),
    });
    const body = await this.#send(
      `/charges/fees/calculate?${query}`,
      undefined,
      "GET",
    );
    const interest = buyerInterestFromQuote(body, installments);
    if (interest == null) throw new Error("PagBank 502: juros_indisponiveis");
    installmentCharge({
      principalCents,
      installments,
      buyerInterestCents: interest,
    });
    return interest;
  }

  /// Uma consulta de taxas vira a grade de 1x a 3x.
  async quoteCardPlans(principalCents: number): Promise<InstallmentOption[]> {
    if (!Number.isInteger(principalCents) || principalCents <= 0) {
      throw new Error("valor");
    }
    const query = new URLSearchParams({
      payment_methods: "CREDIT_CARD",
      value: String(principalCents),
      max_installments: String(maxInstallments),
      max_installments_no_interest: String(interestFreeInstallments),
    });
    const body = await this.#send(
      `/charges/fees/calculate?${query}`,
      undefined,
      "GET",
    );
    const interestByCount: Record<number, number> = {};
    for (
      let count = interestFreeInstallments + 1;
      count <= maxInstallments;
      count++
    ) {
      const interest = buyerInterestFromQuote(body, count);
      if (interest != null) interestByCount[count] = interest;
    }
    return installmentMenu({ principalCents, interestByCount });
  }

  /// Recalcula a parcela no servidor. Até 3x o juro do comprador é zero.
  cardPlan(
    principalCents: number,
    installments = 1,
  ): Promise<InstallmentCharge> {
    const count = Number.isInteger(installments) ? installments : 1;
    if (count > maxInstallments) return Promise.reject(new Error("parcelas"));
    if (count <= interestFreeInstallments) {
      return Promise.resolve(
        installmentCharge({ principalCents, installments: count }),
      );
    }
    return this.quoteBuyerInterest(principalCents, count).then((interest) =>
      installmentCharge({
        principalCents,
        installments: count,
        buyerInterestCents: interest,
      })
    );
  }

  /// ORDE_ é GET /orders/{id}. CHAR_ é GET /orders?charge_id=, a consulta
  /// por parâmetro da API de Pedidos. GET /charges/{id} e GET /charges com
  /// dateCreated/paymentDate não são essa API: o gateway não entrega o
  /// pedido e a doc trata 406 como método que o recurso não aceita.
  readPayment(paymentId: string): Promise<Record<string, unknown>> {
    if (paymentId.startsWith("CHAR_")) {
      const query = new URLSearchParams({ charge_id: paymentId });
      return this.#send(`/orders?${query}`, undefined, "GET").then((body) =>
        orderContainingCharge(body, paymentId)
      );
    }
    const path = paymentId.startsWith("ORDE_")
      ? `/orders/${encodeURIComponent(paymentId)}`
      : `/charges/${encodeURIComponent(paymentId)}`;
    return this.#send(path, undefined, "GET");
  }

  getPayment(paymentId: string): Promise<PaymentView> {
    return this.readPayment(paymentId).then((body) => {
      const normalized = normalizeSelected(
        body,
        paymentId.startsWith("CHAR_") ? paymentId : "",
      );
      const id = paymentId.startsWith("CHAR_")
        ? paymentId
        : persistedPaymentId(body, normalized);
      return {
        id,
        status: stringField(normalized, "status"),
        billingType: stringField(normalized, "billingType"),
        deleted: normalized.deleted === true,
        splitId: optionalString(normalized, "splitId"),
        expiresAt: pixExpiresAt(body),
      };
    });
  }

  /// Saldo em centavos. GET /accounts/balance vem em reais decimais.
  financeBalanceCents(): Promise<number> {
    return this.#send("/accounts/balance", undefined, "GET").then((body) => {
      const read = readAccountBalance(body);
      if (!read.exact || read.field !== "balance") warnBalanceShape();
      return read.cents;
    });
  }

  configureFiscalInfo(_input: object): Promise<void> {
    return Promise.resolve();
  }

  scheduleInvoice(input: { externalReference: string }): Promise<{ id: string; status: string }> {
    return Promise.resolve({
      id: `local_${input.externalReference}`,
      status: "SCHEDULED",
    });
  }

  authorizeInvoice(id: string): Promise<{ id: string; status: string }> {
    return Promise.resolve({ id, status: "SCHEDULED" });
  }

  findInvoiceByReference(_reference: string): Promise<{ id: string; status: string } | null> {
    return Promise.resolve(null);
  }

  getInvoice(id: string): Promise<{
    id: string;
    status: string;
    number: string;
    pdfUrl: string;
    xmlUrl: string;
  }> {
    return Promise.resolve({
      id,
      status: "SCHEDULED",
      number: "",
      pdfUrl: "",
      xmlUrl: "",
    });
  }

  cancelInvoice(_id: string): Promise<void> {
    return Promise.resolve();
  }

  getPixTransaction(id: string): Promise<Record<string, unknown>> {
    return this.readPayment(id);
  }

  confirmedReceivables(): Promise<never[]> {
    return Promise.resolve([]);
  }

  financialTransactions(): Promise<never[]> {
    return Promise.resolve([]);
  }

  createTransfer(input: TransferRequest): Promise<TransferResult> {
    return this.#send("/transfers", transferPayload(input)).then(parseTransfer);
  }

  findTransfer(externalReference: string): Promise<TransferResult | null> {
    return this.#send(
      `/transfers?reference_id=${encodeURIComponent(externalReference)}`,
      undefined,
      "GET",
    ).then((body) => findTransferInList(body, externalReference));
  }

  readTransfer(id: string): Promise<TransferResult> {
    return this.#send(`/transfers/${encodeURIComponent(id)}`, undefined, "GET")
      .then(parseTransfer);
  }

  listWebhooks(): Promise<WebhookView[]> {
    return this.#send("/notifications", undefined, "GET").then(parseWebhookList);
  }

  saveWebhook(body: Record<string, unknown>, id = ""): Promise<void> {
    const path = id
      ? `/notifications/${encodeURIComponent(id)}`
      : "/notifications";
    return this.#send(path, body, id ? "PUT" : "POST").then(() => undefined);
  }

  async #resolvePixPayment(
    input: PixInput,
  ): Promise<PixPaymentRef & { created: boolean; qr?: { payload: string; encodedImage: string } }> {
    const reference = input.externalReference.trim();
    if (!reference) throw new Error("externalReference ausente");
    const existing = await this.#findReusablePix(reference);
    if (existing) {
      const raw = await this.readPayment(existing.id);
      const full = normalizeCharge(raw);
      if (String(full.externalReference ?? "") !== reference) {
        throw new PixReuseRejected();
      }
      full.customer = input.customer;
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
        id: persistedPaymentId(raw, full),
        status: stringField(full, "status"),
        splitId: optionalString(full, "splitId"),
        created: false,
      };
    }
    const order = await this.#createOrder(input, "PIX");
    const charge = firstCharge(order);
    const qr = readQr(charge) ?? readQr(order);
    return {
      id: persistedPaymentId(order, normalizeCharge(order)),
      status: mapStatus(stringField(charge, "status"), charge),
      splitId: splitIdOf(charge),
      created: true,
      qr: qr ?? undefined,
    };
  }

  async #findReusablePix(reference: string): Promise<PixPaymentRef | null> {
    return pickReusablePix(await this.#ordersByReference(reference));
  }

  async #ordersByReference(reference: string): Promise<Record<string, unknown>[]> {
    const query = new URLSearchParams({ reference_id: reference });
    const body = await this.#send(`/orders?${query}`, undefined, "GET");
    return chargesFromList(body).map(normalizeCharge);
  }

  async #createOrder(
    input: PixInput & { creditCardToken?: string; installments?: number; buyerInterestCents?: number },
    method: "PIX" | "CREDIT_CARD",
  ): Promise<Record<string, unknown>> {
    const cents = Math.round(input.value * 100);
    const venueCents = Math.round(input.split.fixedValue * 100);
    const extras = (input.extraSplits ?? []).map((item) => ({
      accountId: item.walletId,
      amountCents: Math.round(item.fixedValue * 100),
    }));
    const split = fixedSplit({
      chargedCents: method === "CREDIT_CARD"
        ? cents
        : cents,
      venueCents,
      venueAccountId: input.split.walletId,
      primaryAccountId: this.#primary(),
      extras,
    });
    let amountCents = cents;
    let plan = installmentCharge({ principalCents: cents, installments: 1 });
    if (method === "CREDIT_CARD") {
      const count = input.installments ?? 1;
      let interest = input.buyerInterestCents;
      if (count > 3 && interest == null) {
        interest = await this.quoteBuyerInterest(cents, count);
      }
      plan = installmentCharge({
        principalCents: cents,
        installments: count,
        buyerInterestCents: interest,
      });
      amountCents = plan.amountCents;
      if (amountCents !== cents) {
        const scaled = fixedSplit({
          chargedCents: amountCents,
          venueCents,
          venueAccountId: input.split.walletId,
          primaryAccountId: this.#primary(),
          extras,
        });
        return await this.#postOrder(input, method, scaled, plan);
      }
    }
    return await this.#postOrder(input, method, split, plan);
  }

  #postOrder(
    input: PixInput & { creditCardToken?: string },
    method: "PIX" | "CREDIT_CARD",
    split: FixedSplit,
    plan: ReturnType<typeof installmentCharge>,
  ): Promise<Record<string, unknown>> {
    const details = input.customerDetails;
    const customer: Record<string, unknown> = {
      name: details?.name || "Jogador",
      email: details?.email || "jogador@escapematch.com.br",
    };
    if (details?.taxId) customer.tax_id = details.taxId;
    const paymentMethod: Record<string, unknown> = method === "PIX"
      ? {
        type: "PIX",
        pix: { expiration_date: pixExpiration(input.dueDate) },
      }
      : {
        type: "CREDIT_CARD",
        installments: plan.installments,
        capture: false,
        soft_descriptor: "EscapeMatch",
        card: cardBody(input.creditCardToken ?? ""),
      };
    // Doc "Criar pedido com QR Code PIX" e "Pedido com divisão com PIX":
    // o Pix interbancário nasce em charges[].payment_method.type = PIX.
    // qr_codes no pedido, com arrangements PAGBANK, é o QR da carteira
    // PagBank e só paga no app PagBank. Não entra neste pedido.
    const order: Record<string, unknown> = {
      reference_id: input.externalReference,
      customer,
      items: [{
        reference_id: input.externalReference,
        name: input.description.slice(0, 80) || "EscapeMatch",
        quantity: 1,
        unit_amount: plan.amountCents,
      }],
      charges: [{
        reference_id: input.externalReference,
        description: input.description.slice(0, 120),
        amount: chargeAmountBody(plan),
        payment_method: paymentMethod,
        splits: pagbankSplitBody(split),
      }],
    };
    if (this.notificationUrl) order.notification_urls = [this.notificationUrl];
    return this.#send("/orders", order);
  }

  #primary(): string {
    const id = this.primaryAccountId.trim();
    if (!id) throw new Error("PAGBANK_ACCOUNT_ID ausente");
    return id;
  }

  /// Cancelar pagamento (POST /charges/{id}/cancel) não documenta header
  /// de idempotência. `x-idempotency-key` está em Criar estorno de
  /// pagamento recorrente (PAYM_), não neste recurso. O erro 40005 de
  /// Pedidos não nomeia o header do cancelamento. A fila usa lease.
  #cancelCharge(
    paymentId: string,
    amountCents = 0,
  ): Promise<Record<string, unknown>> {
    return this.#chargeMoney(paymentId, amountCents).then((target) =>
      this.#send(
        `/charges/${encodeURIComponent(target.chargeId)}/cancel`,
        { amount: { value: target.value } },
      )
    );
  }

  /// A doc de captura e de cancelamento manda amount.value em centavos.
  /// Pedido ORDE_ resolve o CHAR_ gerado no pagamento.
  #chargeMoney(
    paymentId: string,
    amountCents = 0,
  ): Promise<{ chargeId: string; value: number }> {
    const known = Math.round(amountCents);
    if (known > 0 && !paymentId.startsWith("ORDE_")) {
      return Promise.resolve({ chargeId: paymentId, value: known });
    }
    return this.readPayment(paymentId).then((body) => {
      const charge = chargeRecord(body);
      const chargeId = stringField(charge, "id") || paymentId;
      const value = known > 0 ? known : chargeAmountCents(charge);
      if (!chargeId || value <= 0) {
        throw new Error("PagBank 400: amount ausente");
      }
      return { chargeId, value };
    });
  }

  async #pixQrWithRetry(
    paymentId: string,
  ): Promise<{ payload: string; encodedImage: string }> {
    let last: unknown;
    for (let attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await this.sleep(100 * attempt);
      try {
        const body = await this.readPayment(paymentId);
        const qr = readQr(body);
        if (qr?.payload) return qr;
        last = new PixQrUnavailableError(paymentId, "PENDING");
      } catch (error) {
        last = error;
      }
    }
    throw last instanceof Error
      ? last
      : new PixQrUnavailableError(paymentId, "PENDING");
  }

  async #send(
    path: string,
    payload: unknown,
    method = "POST",
    extraHeaders: Record<string, string> = {},
    allowRefresh = true,
  ): Promise<Record<string, unknown>> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      "User-Agent": "EscapeMatch",
      Accept: "application/json",
      ...extraHeaders,
    };
    const init: RequestInit = { method, headers };
    if (method !== "GET") {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(payload ?? {});
    }
    let response: Response;
    try {
      response = await this.fetchFn(`${this.baseUrl}${path}`, init);
    } catch (error) {
      if (isTimeoutError(error)) throw new Error("PagBank 408: timeout");
      throw error;
    }
    if (
      response.status === 401 &&
      allowRefresh &&
      this.#refreshAccess
    ) {
      const next = (await this.#refreshAccess()).trim();
      if (next) {
        this.apiKey = next;
        return this.#send(path, payload, method, extraHeaders, false);
      }
    }
    const text = await response.text();
    const safe = redactOutbound(text, this.apiKey);
    if (!response.ok) {
      throw new Error(`PagBank ${response.status}: ${safe.slice(0, 500)}`);
    }
    if (!text) return {};
    try {
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new Error("Resposta da PagBank inválida");
    }
  }
}

function isTimeoutError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const name = (error as { name?: unknown }).name;
  return name === "TimeoutError" || name === "AbortError";
}

/// A busca por charge_id devolve `{ orders: [...] }`. A resposta é só a
/// cobrança cujo id foi pedido. A primeira do array pode ser uma tentativa
/// recusada. Sem esse CHAR_, é 404.
export function orderContainingCharge(
  body: Record<string, unknown>,
  chargeId: string,
): Record<string, unknown> {
  const sources = Array.isArray(body.orders) ? body.orders : [body];
  for (const item of sources) {
    if (!item || typeof item !== "object") continue;
    const found = findCharge(item as Record<string, unknown>, chargeId);
    if (found) return found;
  }
  throw new Error("PagBank 404: cobrança ausente");
}

function findCharge(
  body: Record<string, unknown>,
  chargeId: string,
): Record<string, unknown> | null {
  const charges = Array.isArray(body.charges) ? body.charges : [];
  for (const item of charges) {
    if (!item || typeof item !== "object") continue;
    const charge = item as Record<string, unknown>;
    if (charge.id === chargeId) return charge;
  }
  if (body.id === chargeId) return body;
  return null;
}

function redactOutbound(text: string, apiKey: string): string {
  const withoutKey = apiKey ? text.split(apiKey).join("[redacted]") : text;
  return redactSensitive(withoutKey).replace(
    /"(security_code|exp_month|exp_year|tax_id|number)"\s*:\s*"(?:\\.|[^"\\])*"/gi,
    '"$1":"[redacted]"',
  );
}

function expiresInSeconds(body: Record<string, unknown>): number {
  const value = body.expires_in;
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

function stringField(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Resposta da PagBank sem ${key}`);
  }
  return value;
}

function optionalString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value === "number") return String(value);
  if (typeof value !== "string") return "";
  return value;
}

function cardBody(token: string): Record<string, unknown> {
  if (token.startsWith("CARD_") || token.startsWith("tok_")) {
    return { id: token, store: true };
  }
  return { encrypted: token, store: true };
}

function pixExpiration(dueDate: string): string {
  if (dueDate.includes("T")) return dueDate;
  return `${dueDate}T23:59:00-03:00`;
}

function firstCharge(order: Record<string, unknown>): Record<string, unknown> {
  const charges = order.charges;
  if (Array.isArray(charges) && charges[0] && typeof charges[0] === "object") {
    return charges[0] as Record<string, unknown>;
  }
  if (typeof order.id === "string" && order.id.length > 0) return order;
  throw new Error("Resposta da PagBank sem charges");
}

function splitIdOf(charge: Record<string, unknown>): string {
  const splits = charge.splits;
  if (splits && typeof splits === "object" && !Array.isArray(splits)) {
    const id = (splits as { id?: unknown }).id;
    if (typeof id === "string") return id;
  }
  if (typeof charge.split_id === "string") return charge.split_id;
  return "";
}

function mapStatus(
  status: string,
  body: Record<string, unknown>,
): string {
  const upper = status.trim().toUpperCase();
  const summary = amountSummary(body);
  if (upper === "CANCELED" || upper === "CANCELLED") {
    if ((summary?.refunded ?? 0) > 0) return "REFUNDED";
    return "CANCELED";
  }
  if (upper === "PAID") return "CONFIRMED";
  if (upper === "AUTHORIZED") return "AUTHORIZED";
  if (upper === "DECLINED") return "CANCELED";
  if (upper === "REFUNDED") return "REFUNDED";
  if (upper === "CONFIRMED" || upper === "RECEIVED" || upper === "PENDING") {
    return upper;
  }
  return "PENDING";
}

function amountSummary(
  body: Record<string, unknown>,
): { refunded?: number } | null {
  const amount = body.amount;
  if (!amount || typeof amount !== "object") return null;
  const summary = (amount as { summary?: unknown }).summary;
  if (!summary || typeof summary !== "object") return null;
  const refunded = (summary as { refunded?: unknown }).refunded;
  return { refunded: typeof refunded === "number" ? refunded : 0 };
}

function normalizeCharge(body: Record<string, unknown>): Record<string, unknown> {
  return normalizeSelected(body, "");
}

function normalizeSelected(
  body: Record<string, unknown>,
  chargeId: string,
): Record<string, unknown> {
  const charge = chargeId.startsWith("CHAR_")
    ? findCharge(body, chargeId)
    : Array.isArray(body.charges)
    ? firstCharge(body)
    : body;
  if (!charge) throw new Error("PagBank 404: cobrança ausente");
  const method = charge.payment_method;
  const type = method && typeof method === "object"
    ? String((method as { type?: unknown }).type ?? "")
    : "";
  const billingType = type === "CREDIT_CARD"
    ? "CREDIT_CARD"
    : type === "PIX"
    ? "PIX"
    : String(charge.billingType ?? "");
  const amount = charge.amount;
  const cents = amount && typeof amount === "object"
    ? Number((amount as { value?: unknown }).value ?? 0)
    : Math.round(Number(charge.value ?? 0) * 100);
  const customer = charge.customer ?? body.customer;
  const customerId = customer && typeof customer === "object"
    ? String((customer as { reference_id?: unknown }).reference_id ??
      (customer as { id?: unknown }).id ?? "")
    : String(charge.customer ?? "");
  return {
    id: charge.id,
    orderId: orderIdOf(body) || orderIdOf(charge),
    status: mapStatus(String(charge.status ?? ""), charge),
    billingType,
    customer: customerId,
    value: cents / 100,
    deleted: charge.deleted === true,
    splitId: splitIdOf(charge),
    split: normalizedReceivers(charge),
    externalReference: charge.reference_id ?? charge.externalReference,
  };
}

function orderIdOf(body: Record<string, unknown>): string {
  if (typeof body.id === "string" && body.id.startsWith("ORDE_")) return body.id;
  if (typeof body.order_id === "string" && body.order_id.startsWith("ORDE_")) {
    return body.order_id;
  }
  if (typeof body.orderId === "string" && body.orderId.startsWith("ORDE_")) {
    return body.orderId;
  }
  return "";
}

function persistedPaymentId(
  body: Record<string, unknown>,
  normalized: Record<string, unknown>,
): string {
  return orderIdOf(body) || orderIdOf(normalized) || stringField(normalized, "id");
}

function chargeRecord(body: Record<string, unknown>): Record<string, unknown> {
  if (Array.isArray(body.charges) && body.charges[0] &&
    typeof body.charges[0] === "object") {
    return body.charges[0] as Record<string, unknown>;
  }
  return body;
}

function chargeAmountCents(charge: Record<string, unknown>): number {
  const amount = charge.amount;
  if (amount && typeof amount === "object") {
    const value = (amount as { value?: unknown }).value;
    if (typeof value === "number" && value > 0) return Math.round(value);
  }
  if (typeof charge.value === "number" && charge.value > 0) {
    return Math.round(charge.value * 100);
  }
  return 0;
}

function pixExpiresAt(body: Record<string, unknown>): string {
  const charge = chargeRecord(body);
  const method = charge.payment_method;
  if (method && typeof method === "object") {
    const pix = (method as { pix?: { expiration_date?: unknown } }).pix;
    if (typeof pix?.expiration_date === "string") return pix.expiration_date;
  }
  const codes = Array.isArray(body.qr_codes) ? body.qr_codes : charge.qr_codes;
  if (Array.isArray(codes) && codes[0] && typeof codes[0] === "object") {
    const date = (codes[0] as { expiration_date?: unknown }).expiration_date;
    if (typeof date === "string") return date;
  }
  return "";
}

function normalizedReceivers(
  charge: Record<string, unknown>,
): { walletId: string; fixedValue: number }[] {
  const splits = charge.splits;
  if (!splits || typeof splits !== "object") {
    return Array.isArray(charge.split) ? charge.split as {
      walletId: string;
      fixedValue: number;
    }[] : [];
  }
  const receivers = (splits as { receivers?: unknown }).receivers;
  if (!Array.isArray(receivers)) return [];
  return receivers.map((item) => {
    const row = item as {
      account?: { id?: string };
      amount?: { value?: number };
    };
    return {
      walletId: row.account?.id ?? "",
      fixedValue: Number(row.amount?.value ?? 0) / 100,
    };
  });
}

function chargesFromList(body: Record<string, unknown>): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  const orders = Array.isArray(body.orders)
    ? body.orders
    : Array.isArray(body.data)
    ? body.data
    : [];
  for (const order of orders) {
    if (!order || typeof order !== "object") continue;
    const record = order as Record<string, unknown>;
    if (Array.isArray(record.charges)) {
      for (const charge of record.charges) {
        if (charge && typeof charge === "object") {
          out.push({
            ...(charge as Record<string, unknown>),
            customer: record.customer,
            order_id: record.id,
          });
        }
      }
    } else if (typeof record.id === "string") {
      out.push(record);
    }
  }
  if (Array.isArray(body.charges)) {
    for (const charge of body.charges) {
      if (charge && typeof charge === "object") {
        out.push(charge as Record<string, unknown>);
      }
    }
  }
  return out;
}

function readQr(
  body: Record<string, unknown>,
): { payload: string; encodedImage: string } | null {
  const texts: string[] = [];
  const images: string[] = [];
  walk(body, texts, images);
  if (texts.length === 0 && images.length === 0) return null;
  return { payload: texts[0] ?? "", encodedImage: images[0] ?? "" };
}

function walk(node: unknown, texts: string[], images: string[]): void {
  if (!node || typeof node !== "object") return;
  if (Array.isArray(node)) {
    for (const item of node) walk(item, texts, images);
    return;
  }
  const record = node as Record<string, unknown>;
  for (const [key, value] of Object.entries(record)) {
    if (typeof value === "string" && value.startsWith("000201")) texts.push(value);
    if (key === "payload" && typeof value === "string" && value.length > 0) {
      texts.push(value);
    }
    if (
      typeof value === "string" &&
      (key === "encodedImage" || key === "base64" || key === "image") &&
      value.length > 8
    ) {
      images.push(value);
    }
    if (key === "text" && typeof value === "string" && value.length > 20) {
      texts.push(value);
    }
    if (value && typeof value === "object") walk(value, texts, images);
  }
}
