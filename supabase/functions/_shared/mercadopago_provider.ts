// Mercado Pago, marketplace. O pagamento nasce com o access_token OAuth
// da casa. application_fee é a comissão da EscapeMatch, em reais.
// POST /v1/payments com capture=false reserva. PUT capture=true captura.
// PUT status=cancelled cancela a reserva. POST /v1/payments/{id}/refunds
// estorna. O número do cartão não entra: só o token feito no aparelho.
// O access token dura 180 dias e é renovado antes disso.

import {
  centsToReais,
  looksLikePan,
  ProviderUnsupported,
  scrubSecret,
  timingSafeEqualText,
  type ActionResult,
  type CardAuthInput,
  type FetchLike,
  type PaymentProvider,
  type PixCreateInput,
  type PixCreateResult,
  type RefundInput,
} from "./payment_provider.ts";
import type { EnvLike } from "./http.ts";

export const mercadoPagoApiBaseUrl = "https://api.mercadopago.com";
export const mercadoPagoAuthBaseUrl = "https://auth.mercadopago.com.br";

const oauthLifetimeMs = 180 * 24 * 60 * 60 * 1000;
const refreshBeforeMs = 30 * 24 * 60 * 60 * 1000;

export function oauthExpiresAt(now: Date): Date {
  return new Date(now.getTime() + oauthLifetimeMs);
}

/// Renova quando falta menos de 30 dias para os 180. Não espera o token morrer.
export function shouldRefreshOauth(expiresAt: Date, now: Date): boolean {
  return expiresAt.getTime() - now.getTime() < refreshBeforeMs;
}

export function mpAuthorizationUrl(input: {
  clientId: string;
  redirectUri: string;
  state: string;
}): string {
  const url = new URL(`${mercadoPagoAuthBaseUrl}/authorization`);
  url.searchParams.set("client_id", input.clientId);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("platform_id", "mp");
  url.searchParams.set("redirect_uri", input.redirectUri);
  url.searchParams.set("state", input.state);
  return url.toString();
}

export type OauthToken = {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
};

export function exchangeAuthorizationCode(
  input: {
    clientId: string;
    clientSecret: string;
    code: string;
    redirectUri: string;
    now?: Date;
  },
  fetchFn: FetchLike = fetch,
): Promise<OauthToken> {
  return requestOauthToken({
    client_id: input.clientId,
    client_secret: input.clientSecret,
    grant_type: "authorization_code",
    code: input.code,
    redirect_uri: input.redirectUri,
  }, input.clientSecret, input.now ?? new Date(), fetchFn);
}

export function refreshAccessToken(
  input: {
    clientId: string;
    clientSecret: string;
    refreshToken: string;
    now?: Date;
  },
  fetchFn: FetchLike = fetch,
): Promise<OauthToken> {
  return requestOauthToken({
    client_id: input.clientId,
    client_secret: input.clientSecret,
    grant_type: "refresh_token",
    refresh_token: input.refreshToken,
  }, input.clientSecret, input.now ?? new Date(), fetchFn);
}

async function requestOauthToken(
  body: Record<string, string>,
  secret: string,
  now: Date,
  fetchFn: FetchLike,
): Promise<OauthToken> {
  const response = await fetchFn(`${mercadoPagoApiBaseUrl}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`Mercado Pago ${response.status}`);
  const payload = await response.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const accessToken = typeof payload?.access_token === "string"
    ? payload.access_token
    : "";
  const refreshToken = typeof payload?.refresh_token === "string"
    ? payload.refresh_token
    : "";
  if (!accessToken || !refreshToken) throw new Error("Mercado Pago token");
  if (secret && (accessToken.includes(secret) || refreshToken === secret)) {
    throw new Error(scrubSecret("token inválido", secret));
  }
  return {
    accessToken,
    refreshToken,
    expiresAt: oauthExpiresAt(now).toISOString(),
  };
}

export function mpAccessTokenIsTest(value: string | undefined): boolean {
  const token = (value ?? "").trim();
  return token.startsWith("TEST-") && token.length >= 20;
}

/// `sandbox` só com o valor exato. Vazio, `production` ou qualquer outro
/// valor fica em produção.
export function mpEnvMode(env: EnvLike): "sandbox" | "production" {
  try {
    const raw = (env.get("MP_ENV") ?? "").trim().toLowerCase();
    if (raw === "sandbox") return "sandbox";
  } catch {
    return "production";
  }
  return "production";
}

/// Token da plataforma no lugar do OAuth da casa.
/// Em `MP_ENV=sandbox` vale o token do painel, inclusive `APP_USR-`.
/// Sem a variável, `TEST-` continua sinal de sandbox.
/// `MP_ENV=production` ou outro valor não usa o token da plataforma.
export function mpPlatformFallback(env: EnvLike): string | null {
  let declared = "";
  try {
    declared = (env.get("MP_ENV") ?? "").trim().toLowerCase();
  } catch {
    return null;
  }
  let token = "";
  try {
    token = (env.get("MP_ACCESS_TOKEN") ?? "").trim();
  } catch {
    return null;
  }
  if (token.length < 20) return null;
  if (declared === "sandbox") return token;
  if (declared === "" && mpAccessTokenIsTest(token)) return token;
  return null;
}

export class MercadoPagoProvider implements PaymentProvider {
  readonly name = "mercadopago" as const;

  constructor(private readonly fetchFn: FetchLike = fetch) {}

  static fromEnv(_env: EnvLike, fetchFn?: FetchLike): MercadoPagoProvider {
    return new MercadoPagoProvider(fetchFn);
  }

  createPix(_input: PixCreateInput): Promise<PixCreateResult> {
    return Promise.reject(new ProviderUnsupported(this.name, "createPix"));
  }

  async authorizeCard(input: CardAuthInput): Promise<ActionResult> {
    if (looksLikePan(input.token) || looksLikePan(input.paymentMethodId)) {
      throw new Error("A cobrança não recebe dados do cartão.");
    }
    if (!input.accessToken.trim()) throw new Error("access_token ausente");
    if (!input.payerEmail.includes("@")) throw new Error("email ausente");
    const body = {
      transaction_amount: centsToReais(input.transactionAmountCents),
      token: input.token,
      description: input.description.slice(0, 140),
      installments: 1,
      payment_method_id: input.paymentMethodId,
      payer: { email: input.payerEmail },
      capture: false,
      application_fee: centsToReais(input.applicationFeeCents),
    };
    const payload = await this.#send("/v1/payments", body, input.accessToken, {
      "X-Idempotency-Key": input.idempotencyKey,
    });
    return mapPayment(payload);
  }

  async capture(providerRef: string, accessToken = ""): Promise<ActionResult> {
    const payload = await this.#send(
      `/v1/payments/${encodeURIComponent(providerRef)}`,
      { capture: true },
      accessToken,
      { "X-Idempotency-Key": `capture:${providerRef}` },
      "PUT",
    );
    const result = mapPayment(payload);
    if (result.status !== "paid") throw new Error("captura recusada");
    return result;
  }

  cancelAuthorization(
    providerRef: string,
    accessToken = "",
  ): Promise<ActionResult> {
    return this.#send(
      `/v1/payments/${encodeURIComponent(providerRef)}`,
      { status: "cancelled" },
      accessToken,
      { "X-Idempotency-Key": `cancel:${providerRef}` },
      "PUT",
    ).then(mapPayment);
  }

  async refund(input: RefundInput): Promise<ActionResult> {
    const token = input.accessToken ?? "";
    const partial = input.chargeCents != null &&
      input.valueCents < input.chargeCents;
    const body = partial ? { amount: centsToReais(input.valueCents) } : {};
    const payload = await this.#send(
      `/v1/payments/${encodeURIComponent(input.providerRef)}/refunds`,
      body,
      token,
      { "X-Idempotency-Key": input.idempotencyKey ?? input.correlationId },
    );
    const id = payload.id == null ? input.providerRef : String(payload.id);
    return { id, status: "refunded" };
  }

  getPayment(providerRef: string, accessToken = ""): Promise<ActionResult> {
    return this.#send(
      `/v1/payments/${encodeURIComponent(providerRef)}`,
      undefined,
      accessToken,
      {},
      "GET",
    ).then(mapPayment);
  }

  async #send(
    path: string,
    body: Record<string, unknown> | undefined,
    accessToken: string,
    extra: Record<string, string>,
    method = "POST",
  ): Promise<Record<string, unknown>> {
    if (!accessToken.trim()) throw new Error("access_token ausente");
    const headers: Record<string, string> = {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
      ...extra,
    };
    const init: RequestInit = { method, headers };
    if (body && method !== "GET") {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    let response: Response;
    try {
      response = await this.fetchFn(`${mercadoPagoApiBaseUrl}${path}`, init);
    } catch (error) {
      const message = error instanceof Error ? error.message : "rede";
      throw new Error(scrubSecret(message, accessToken));
    }
    if (!response.ok) throw new Error(`Mercado Pago ${response.status}`);
    const payload = await response.json().catch(() => null);
    if (!payload || typeof payload !== "object") {
      throw new Error("Mercado Pago resposta");
    }
    return payload as Record<string, unknown>;
  }
}

export function mapMpStatus(status: string): string {
  const value = status.trim().toLowerCase();
  if (value === "approved") return "paid";
  if (value === "authorized") return "authorized";
  if (value === "cancelled") return "cancelled";
  if (value === "rejected") return "failed";
  if (value === "refunded") return "refunded";
  if (value === "charged_back" || value === "in_mediation") return "charged_back";
  if (value === "pending" || value === "in_process") return "pending";
  return "pending";
}

/// Reserva ainda em análise continua pending. Chargeback não vira failed.
export function storedCardStatus(remote: string): string {
  if (remote === "authorized" || remote === "pending" || remote === "charged_back") {
    return remote;
  }
  return "failed";
}

function mapPayment(payload: Record<string, unknown>): ActionResult {
  const id = payload.id == null ? "" : String(payload.id);
  const status = typeof payload.status === "string" ? payload.status : "";
  return {
    id,
    status: mapMpStatus(status),
    captured: payload.captured === true,
  };
}

export function mpWebhookManifest(input: {
  dataId: string;
  requestId: string;
  ts: string;
}): string {
  const id = input.dataId.trim().toLowerCase();
  return `id:${id};request-id:${input.requestId};ts:${tsOrEmpty(input.ts)};`;
}

function tsOrEmpty(value: string): string {
  return value.trim();
}

export async function mpSignatureMatches(input: {
  secret: string;
  manifest: string;
  v1: string;
}): Promise<boolean> {
  if (input.secret.length < 16 || !input.v1) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(input.secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(input.manifest),
  );
  const hex = [...new Uint8Array(signed)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return timingSafeEqualText(hex, input.v1.trim().toLowerCase());
}

export function parseSignatureHeader(header: string | null): {
  ts: string;
  v1: string;
} {
  let ts = "";
  let v1 = "";
  for (const part of (header ?? "").split(",")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const key = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (key === "ts") ts = value;
    if (key === "v1") v1 = value;
  }
  return { ts, v1 };
}
