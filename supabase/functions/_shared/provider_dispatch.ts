// Captura, cancelamento e estorno das cobranças que não são Asaas.
// O livro continua em applyPaymentTransition. NFS-e não é emitida aqui.

import { logCaught } from "./client_error.ts";
import { MercadoPagoProvider } from "./mercadopago_provider.ts";
import {
  applyPaymentTransition,
  creditLedger,
  reverseLedger,
  type ChargeRow,
} from "./ledger.ts";
import {
  denoEnv,
  houseDebitForRefund,
  isAlternateProvider,
  readEnv,
} from "./payment_provider.ts";
import { WooviProvider } from "./woovi_provider.ts";
import type { EnvLike } from "./http.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type AlternateCharge = ChargeRow & {
  status: string;
  provider?: string | null;
  provider_ref: string | null;
  billing_type: string;
  provider_end_to_end_id?: string | null;
  house_pix_key?: string | null;
  house_fixed_cents?: number | null;
};

export type AlternateGate = {
  env?: EnvLike;
  woovi?: WooviProvider;
  mercadoPago?: MercadoPagoProvider;
  now?: Date;
};

export async function settleAlternateCharge(
  admin: Admin,
  row: AlternateCharge,
  gate: AlternateGate = {},
): Promise<void> {
  if (!isAlternateProvider(row.provider) || !row.provider_ref) return;
  if (row.provider === "mercadopago" && row.status === "authorized" &&
    row.billing_type === "CREDIT_CARD") {
    const token = await accessToken(admin, gate, row.venue_id);
    const mp = gate.mercadoPago ?? MercadoPagoProvider.fromEnv(envOf(gate));
    const captured = await mp.capture(row.provider_ref, token);
    if (captured.status !== "paid") return;
    const transition = await applyPaymentTransition(admin, row.id, "paid", true);
    if (transition.status !== "paid") return;
    await withdrawAfterSession(admin, row, gate);
    return;
  }
  if (row.status === "paid") {
    await creditLedger(admin, row);
    await withdrawAfterSession(admin, row, gate);
  }
}

export async function releaseAlternateCharge(
  admin: Admin,
  row: AlternateCharge,
  gate: AlternateGate = {},
): Promise<void> {
  if (!isAlternateProvider(row.provider)) return;
  if (!row.provider_ref) {
    await applyPaymentTransition(admin, row.id, "cancelled", false);
    return;
  }
  if (row.status === "paid") {
    await refundAlternate(admin, row, gate, row.amount_cents);
    await reverseLedger(admin, row);
    return;
  }
  if (row.provider === "mercadopago") {
    const token = await accessToken(admin, gate, row.venue_id);
    const mp = gate.mercadoPago ?? MercadoPagoProvider.fromEnv(envOf(gate));
    await mp.cancelAuthorization(row.provider_ref, token);
  } else {
    const woovi = gate.woovi ?? WooviProvider.fromEnv(envOf(gate));
    await woovi.cancelAuthorization(row.provider_ref);
  }
  await applyPaymentTransition(admin, row.id, "cancelled", false);
}

export async function refundAlternate(
  admin: Admin,
  row: AlternateCharge,
  gate: AlternateGate,
  refundCents: number,
): Promise<void> {
  if (!row.provider_ref) throw new Error("provider_ref ausente");
  const houseSplit = Number(row.house_fixed_cents) || 0;
  const debit = houseDebitForRefund({
    refundCents,
    chargeCents: row.amount_cents,
    houseSplitCents: houseSplit,
  });
  if (row.provider === "woovi") {
    const woovi = gate.woovi ?? WooviProvider.fromEnv(envOf(gate));
    await woovi.refund({
      providerRef: row.provider_ref,
      valueCents: refundCents,
      chargeCents: row.amount_cents,
      correlationId: `refund:${row.id}:${refundCents}`,
      endToEndId: row.provider_end_to_end_id ?? "",
      housePixKey: row.house_pix_key ?? "",
      houseDebitCents: debit,
    });
    return;
  }
  const token = await accessToken(admin, gate, row.venue_id);
  const mp = gate.mercadoPago ?? MercadoPagoProvider.fromEnv(envOf(gate));
  await mp.refund({
    providerRef: row.provider_ref,
    valueCents: refundCents,
    chargeCents: row.amount_cents,
    correlationId: `refund:${row.id}:${refundCents}`,
    accessToken: token,
    idempotencyKey: `refund:${row.id}:${refundCents}`,
  });
}

async function withdrawAfterSession(
  admin: Admin,
  row: AlternateCharge,
  gate: AlternateGate,
): Promise<void> {
  if (row.provider !== "woovi" || !row.house_pix_key) return;
  try {
    const { data } = await admin.from("provider_payout_accounts")
      .select("auto_withdraw, status, pix_key")
      .eq("venue_id", row.venue_id)
      .eq("provider", "woovi")
      .maybeSingle();
    if (!data || data.auto_withdraw !== true || data.status !== "active") return;
    const cents = Number(row.house_fixed_cents) || 0;
    if (cents <= 0) return;
    const woovi = gate.woovi ?? WooviProvider.fromEnv(envOf(gate));
    await woovi.withdraw(text(data.pix_key) || row.house_pix_key, cents);
  } catch (error) {
    logCaught("woovi-withdraw", error);
  }
}

async function accessToken(
  admin: Admin | null,
  gate: AlternateGate,
  venueId: string,
): Promise<string> {
  if (admin && typeof admin.rpc === "function") {
    const loaded = await admin.rpc("read_provider_oauth", {
      p_venue_id: venueId,
      p_provider: "mercadopago",
    });
    const token = loaded?.data?.access_token;
    if (typeof token === "string" && token.trim()) return token;
  }
  const fallback = readEnv(envOf(gate), "MP_ACCESS_TOKEN");
  if (!fallback.trim()) throw new Error("oauth ausente");
  return fallback.trim();
}

function envOf(gate: AlternateGate): EnvLike {
  return gate.env ?? denoEnv();
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}
