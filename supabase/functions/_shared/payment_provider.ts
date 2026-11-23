// Porta única dos provedores. Pix vai para a Woovi. Cartão vai para
// o Mercado Pago. Cobrança gravada com provider asaas é só leitura.

import type { EnvLike } from "./http.ts";

export const groupUnconfirmedNotice =
  "Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.";

export type PaymentsStack = "woovi";

export type ChargeProviderName =
  | "asaas"
  | "woovi"
  | "mercadopago"
  | "points";

export type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export type SplitLine = {
  pixKey: string;
  valueCents: number;
  splitType: "SPLIT_SUB_ACCOUNT";
};

export type PixCreateInput = {
  correlationId: string;
  valueCents: number;
  comment: string;
  splits: SplitLine[];
};

export type PixCreateResult = {
  providerRef: string;
  status: string;
  brCode: string;
  qrCodeImage: string;
  endToEndId: string;
};

export type CardAuthInput = {
  token: string;
  paymentMethodId: string;
  transactionAmountCents: number;
  applicationFeeCents: number;
  description: string;
  payerEmail: string;
  idempotencyKey: string;
  accessToken: string;
};

export type ActionResult = {
  id: string;
  status: string;
  endToEndId?: string;
  captured?: boolean;
};

export type RefundInput = {
  providerRef: string;
  valueCents: number;
  chargeCents?: number;
  correlationId: string;
  endToEndId?: string;
  housePixKey?: string;
  houseDebitCents?: number;
  accessToken?: string;
  idempotencyKey?: string;
};

/// O que create-charge, a liquidação e o estorno pedem aos dois adaptadores.
export interface PaymentProvider {
  readonly name: "woovi" | "mercadopago";
  createPix(input: PixCreateInput): Promise<PixCreateResult>;
  authorizeCard(input: CardAuthInput): Promise<ActionResult>;
  capture(providerRef: string, accessToken?: string): Promise<ActionResult>;
  cancelAuthorization(
    providerRef: string,
    accessToken?: string,
  ): Promise<ActionResult>;
  refund(input: RefundInput): Promise<ActionResult>;
  getPayment(providerRef: string, accessToken?: string): Promise<ActionResult>;
}

export class ProviderUnsupported extends Error {
  constructor(provider: string, operation: string) {
    super(`${provider} não faz ${operation}`);
    this.name = "ProviderUnsupported";
  }
}

export function denoEnv(): EnvLike {
  return {
    get(name: string): string | undefined {
      try {
        return Deno.env.get(name);
      } catch {
        return undefined;
      }
    },
  };
}

export function readEnv(env: EnvLike, name: string): string {
  try {
    return env.get(name) ?? "";
  } catch {
    return "";
  }
}

/// Pix vai para a Woovi. Cartão vai para o Mercado Pago.
/// `asaas` não é opção: cobrança antiga com esse provider é só leitura.
export function providerForBilling(
  billingType: string,
): "woovi" | "mercadopago" {
  return billingType === "CREDIT_CARD" ? "mercadopago" : "woovi";
}

export function isHistoricalAsaas(
  provider: string | null | undefined,
): boolean {
  return provider === "asaas";
}

export function isAlternateProvider(provider: string | null | undefined): boolean {
  return provider === "woovi" || provider === "mercadopago";
}

/// O estorno do Pix sai da conta principal. A parte da casa volta
/// por um débito na subconta, na mesma proporção do valor estornado.
export function houseDebitForRefund(input: {
  refundCents: number;
  chargeCents: number;
  houseSplitCents: number;
}): number {
  const refundCents = input.refundCents;
  const chargeCents = input.chargeCents;
  const houseSplitCents = input.houseSplitCents;
  if (!Number.isInteger(refundCents) || refundCents <= 0) return 0;
  if (!Number.isInteger(chargeCents) || chargeCents <= 0) return 0;
  if (!Number.isInteger(houseSplitCents) || houseSplitCents <= 0) return 0;
  if (refundCents >= chargeCents) return Math.min(houseSplitCents, chargeCents);
  const share = Math.round((houseSplitCents * refundCents) / chargeCents);
  return Math.min(Math.max(share, 0), houseSplitCents);
}

export function centsToReais(cents: number): number {
  if (!Number.isInteger(cents) || cents < 0) throw new Error("valor");
  return cents / 100;
}

export function looksLikePan(value: string): boolean {
  const digits = value.replace(/\s+/g, "");
  return /^\d{13,19}$/.test(digits);
}

export function timingSafeEqualText(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  const length = Math.max(a.length, b.length);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < length; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

export function scrubSecret(text: string, secret: string): string {
  const value = secret.trim();
  if (value.length < 8) return text;
  return text.split(value).join("[redigido]");
}

/// A diferença entre o total e a soma dos splits fica na conta principal.
/// A reserva de pontos, quando cabe na comissão, é outra SPLIT_SUB_ACCOUNT.
export function wooviSplits(input: {
  housePixKey: string;
  houseCents: number;
  chargeCents: number;
  reservePixKey?: string;
  referralCents?: number;
}): SplitLine[] {
  const houseKey = input.housePixKey.trim();
  if (!houseKey) throw new Error("pix da casa ausente");
  if (
    !Number.isInteger(input.houseCents) || input.houseCents < 0 ||
    !Number.isInteger(input.chargeCents) || input.chargeCents <= 0 ||
    input.houseCents > input.chargeCents
  ) {
    throw new Error("split");
  }
  const lines: SplitLine[] = [];
  if (input.houseCents > 0) {
    lines.push({
      pixKey: houseKey,
      valueCents: input.houseCents,
      splitType: "SPLIT_SUB_ACCOUNT",
    });
  }
  const reserveKey = (input.reservePixKey ?? "").trim();
  const referral = input.referralCents ?? 0;
  const used = lines.reduce((sum, line) => sum + line.valueCents, 0);
  if (
    reserveKey &&
    reserveKey !== houseKey &&
    Number.isInteger(referral) &&
    referral > 0 &&
    used + referral <= input.chargeCents
  ) {
    lines.push({
      pixKey: reserveKey,
      valueCents: referral,
      splitType: "SPLIT_SUB_ACCOUNT",
    });
  }
  return lines;
}
