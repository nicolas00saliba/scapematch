// Alerta diário do saldo disponível da conta PJ.
// A leitura é a mesma de GET /accounts/balance (financeBalanceCents).
// Não liga PAGBANK_CAC_TRANSFERS e não pede transferência.

import { captureOpsAlert, type OpsEnv, type OpsFetch } from "./sentry_ops.ts";

export const defaultLowBalanceAlertCents = 100_000;

/// Abaixo do limite alerta. No limite e acima, não.
export function shouldAlertLowBalance(
  availableCents: number,
  limitCents: number,
): boolean {
  if (!Number.isInteger(availableCents) || availableCents < 0) return false;
  if (!Number.isInteger(limitCents) || limitCents < 0) return false;
  return availableCents < limitCents;
}

export function lowBalanceLimit(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 1_000_000_000) {
    return defaultLowBalanceAlertCents;
  }
  return parsed;
}

/// O corpo do alerta é só escopo e código. O saldo não entra no log.
export async function alertLowPjBalance(input: {
  env: OpsEnv;
  fetchFn: OpsFetch;
  availableCents: number;
  limitCents: number;
}): Promise<boolean> {
  if (!shouldAlertLowBalance(input.availableCents, input.limitCents)) {
    return false;
  }
  await captureOpsAlert(input.env, input.fetchFn, {
    scope: "pagbank-balance",
    code: "low_balance",
  });
  return true;
}
