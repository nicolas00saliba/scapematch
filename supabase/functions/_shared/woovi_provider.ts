// Woovi, só sandbox por padrão. Header Authorization é o APP_ID, sem Bearer.
// Cobrança: POST /api/v1/charge com splits SPLIT_SUB_ACCOUNT na pixKey
// da subconta. O que não entra no split fica na conta principal.
// Estorno: POST /api/v1/refund. O valor sai da conta principal, então
// a parte da casa é debitada em POST /api/v1/subaccount/{pixKey}/debit.
// Saldo: GET /api/v1/subaccount/{pixKey}. Saque: POST .../withdraw.

import {
  groupUnconfirmedNotice,
  looksLikePan,
  ProviderUnsupported,
  readEnv,
  scrubSecret,
  type ActionResult,
  type CardAuthInput,
  type FetchLike,
  type PaymentProvider,
  type PixCreateInput,
  type PixCreateResult,
  type RefundInput,
  type SplitLine,
} from "./payment_provider.ts";
import type { EnvLike } from "./http.ts";

export const wooviSandboxBaseUrl = "https://api.woovi-sandbox.com";
export const wooviProductionBaseUrl = "https://api.woovi.com";

export function wooviBaseUrl(env: EnvLike): string {
  const raw = (readEnv(env, "WOOVI_BASE_URL") || wooviSandboxBaseUrl)
    .replace(/\/$/, "");
  if (raw !== wooviSandboxBaseUrl && raw !== wooviProductionBaseUrl) {
    throw new Error("WOOVI_BASE_URL inválida");
  }
  return raw;
}

export function isWooviSandbox(baseUrl: string): boolean {
  return baseUrl.replace(/\/$/, "") === wooviSandboxBaseUrl;
}

type Json = Record<string, unknown>;

export class WooviProvider implements PaymentProvider {
  readonly name = "woovi" as const;

  constructor(
    private readonly appId: string,
    private readonly baseUrl: string,
    private readonly fetchFn: FetchLike = fetch,
  ) {
    if (!appId.trim()) throw new Error("WOOVI_APP_ID ausente");
    const base = baseUrl.replace(/\/$/, "");
    if (base !== wooviSandboxBaseUrl && base !== wooviProductionBaseUrl) {
      throw new Error("WOOVI_BASE_URL inválida");
    }
    this.baseUrl = base;
  }

  static fromEnv(env: EnvLike, fetchFn?: FetchLike): WooviProvider {
    return new WooviProvider(
      readEnv(env, "WOOVI_APP_ID").trim(),
      wooviBaseUrl(env),
      fetchFn,
    );
  }

  get sandbox(): boolean {
    return isWooviSandbox(this.baseUrl);
  }

  createPix(input: PixCreateInput): Promise<PixCreateResult> {
    this.#assertMoney(input.valueCents);
    const splits = input.splits.map((line) => this.#split(line));
    const splitSum = splits.reduce((sum, line) => sum + line.value, 0);
    if (splitSum > input.valueCents) throw new Error("split");
    return this.#send("/api/v1/charge", {
      correlationID: input.correlationId,
      value: input.valueCents,
      comment: input.comment.slice(0, 140),
      splits,
    }).then((body) => {
      const charge = record(body.charge);
      const ref = text(charge.correlationID) || input.correlationId;
      return {
        providerRef: ref,
        status: mapWooviChargeStatus(text(charge.status)),
        brCode: text(charge.brCode),
        qrCodeImage: text(charge.qrCodeImage),
        endToEndId: "",
      };
    });
  }

  authorizeCard(_input: CardAuthInput): Promise<ActionResult> {
    return Promise.reject(new ProviderUnsupported(this.name, "authorizeCard"));
  }

  capture(providerRef: string): Promise<ActionResult> {
    return Promise.reject(
      new ProviderUnsupported(this.name, `capture ${providerRef}`),
    );
  }

  cancelAuthorization(providerRef: string): Promise<ActionResult> {
    return this.#send(
      `/api/v1/charge/${encodeURIComponent(providerRef)}`,
      undefined,
      "DELETE",
    ).then(() => ({ id: providerRef, status: "cancelled" }));
  }

  /// Estorno total ou parcial. Em seguida debita a parte da casa,
  /// porque o reembolso não sai da subconta.
  async refund(input: RefundInput): Promise<ActionResult> {
    this.#assertMoney(input.valueCents);
    if (!input.endToEndId?.trim()) throw new Error("endToEndId ausente");
    const refunded = await this.#send("/api/v1/refund", {
      correlationID: input.correlationId,
      transactionEndToEndId: input.endToEndId,
      value: input.valueCents,
      comment: groupUnconfirmedNotice.slice(0, 140),
    });
    const refund = record(refunded.refund);
    const debit = input.houseDebitCents ?? 0;
    if (debit > 0) {
      if (!input.housePixKey?.trim()) throw new Error("pix da casa ausente");
      const full = input.chargeCents == null ||
        input.valueCents >= input.chargeCents;
      await this.debitSubaccount(
        input.housePixKey,
        debit,
        full ? "Estorno" : "Estorno parcial",
      );
    }
    return {
      id: text(refund.correlationID) || input.correlationId,
      status: "refunded",
      endToEndId: input.endToEndId,
    };
  }

  getPayment(providerRef: string): Promise<ActionResult> {
    return this.#send(
      `/api/v1/charge/${encodeURIComponent(providerRef)}`,
      undefined,
      "GET",
    ).then((body) => {
      const charge = record(body.charge);
      const pix = record(charge.pix ?? body.pix);
      return {
        id: text(charge.correlationID) || providerRef,
        status: mapWooviChargeStatus(text(charge.status)),
        endToEndId: text(pix.endToEndId),
      };
    });
  }

  createSubaccount(input: { name: string; pixKey: string }): Promise<{
    name: string;
    pixKey: string;
    balanceCents: number;
  }> {
    if (looksLikePan(input.pixKey)) throw new Error("pix inválida");
    return this.#send("/api/v1/subaccount", {
      name: input.name.slice(0, 80),
      pixKey: input.pixKey.trim(),
    }).then((body) => {
      const account = record(body.subAccount ?? body.SubAccount);
      return {
        name: text(account.name),
        pixKey: text(account.pixKey) || input.pixKey.trim(),
        balanceCents: numberOrZero(account.balance),
      };
    });
  }

  balance(pixKey: string): Promise<number> {
    return this.#send(
      `/api/v1/subaccount/${encodeURIComponent(pixKey)}`,
      undefined,
      "GET",
    ).then((body) => {
      const account = record(body.SubAccount ?? body.subAccount);
      return numberOrZero(account.balance);
    });
  }

  withdraw(pixKey: string, valueCents?: number): Promise<{
    status: string;
    valueCents: number;
  }> {
    const body: Json = {};
    if (valueCents != null) {
      this.#assertMoney(valueCents);
      body.value = valueCents;
    }
    return this.#send(
      `/api/v1/subaccount/${encodeURIComponent(pixKey)}/withdraw`,
      body,
    ).then((payload) => {
      const withdrawal = record(payload.withdrawal);
      return {
        status: text(withdrawal.status) || "success",
        valueCents: numberOrZero(withdrawal.value ?? valueCents),
      };
    });
  }

  debitSubaccount(
    pixKey: string,
    valueCents: number,
    description: string,
  ): Promise<void> {
    this.#assertMoney(valueCents);
    return this.#send(
      `/api/v1/subaccount/${encodeURIComponent(pixKey)}/debit`,
      { value: valueCents, description: description.slice(0, 140) },
    ).then(() => undefined);
  }

  #split(line: SplitLine): { value: number; pixKey: string; splitType: string } {
    this.#assertMoney(line.valueCents);
    const pixKey = line.pixKey.trim();
    if (!pixKey || line.splitType !== "SPLIT_SUB_ACCOUNT") throw new Error("split");
    return { value: line.valueCents, pixKey, splitType: "SPLIT_SUB_ACCOUNT" };
  }

  #assertMoney(cents: number): void {
    if (!Number.isInteger(cents) || cents <= 0) throw new Error("valor");
  }

  async #send(path: string, body: Json | undefined, method = "POST"): Promise<Json> {
    const headers: Record<string, string> = {
      Authorization: this.appId,
      Accept: "application/json",
    };
    const init: RequestInit = { method, headers };
    if (body && method !== "GET" && method !== "DELETE") {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    let response: Response;
    try {
      response = await this.fetchFn(`${this.baseUrl}${path}`, init);
    } catch (error) {
      const message = error instanceof Error ? error.message : "rede";
      throw new Error(scrubSecret(message, this.appId));
    }
    if (!response.ok) {
      throw new Error(`Woovi ${response.status}`);
    }
    if (method === "DELETE") return {};
    const payload = await response.json().catch(() => null);
    if (!payload || typeof payload !== "object") throw new Error("Woovi resposta");
    return payload as Json;
  }
}

export function mapWooviChargeStatus(status: string): string {
  const value = status.trim().toUpperCase();
  if (value === "COMPLETED" || value === "PAID") return "paid";
  if (value === "EXPIRED") return "cancelled";
  if (value === "REFUNDED") return "refunded";
  return "pending";
}

export function wooviEventStatus(event: string): string | null {
  const name = event.trim().toUpperCase();
  if (name === "OPENPIX:CHARGE_COMPLETED") return "paid";
  if (name === "OPENPIX:CHARGE_EXPIRED") return "cancelled";
  if (name.includes("REFUND")) return "refunded";
  return null;
}

function record(value: unknown): Json {
  return value && typeof value === "object" ? value as Json : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberOrZero(value: unknown): number {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isInteger(number) && number >= 0 ? number : 0;
}
