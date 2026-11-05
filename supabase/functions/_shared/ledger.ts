export type ChargeRow = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
};

export type TransitionResult = {
  applied: boolean;
  status: string;
  paid_at: string | null;
  refunded_at: string | null;
};

type LedgerRpcError = { code?: string; message?: string } | null;

type Admin = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: LedgerRpcError }>;
};

const sqlState = /^[0-9A-Z]{5}$/;

function throwLedgerError(error: { code?: string }): never {
  const code = error.code && sqlState.test(error.code) ? error.code : "unknown";
  console.error(JSON.stringify({ scope: "ledger", code }));
  throw new Error("ledger_write_failed");
}

function asTransition(data: unknown): TransitionResult {
  const row = data && typeof data === "object"
    ? data as Record<string, unknown>
    : {};
  return {
    applied: row.applied === true,
    status: typeof row.status === "string" ? row.status : "",
    paid_at: typeof row.paid_at === "string" ? row.paid_at : null,
    refunded_at: typeof row.refunded_at === "string" ? row.refunded_at : null,
  };
}

/// A função SQL trava a cobrança, aplica a transição e grava o livro
/// na mesma transação. Duplicata fica no ON CONFLICT. Qualquer erro
/// da chamada é lançado para o webhook responder 5xx.
export async function applyPaymentTransition(
  admin: Admin,
  chargeId: string,
  nextStatus: string,
  credit: boolean,
): Promise<TransitionResult> {
  const { data, error } = await admin.rpc("apply_payment_transition", {
    p_charge_id: chargeId,
    p_next_status: nextStatus,
    p_credit: credit,
  });
  if (error) throwLedgerError(error);
  const result = asTransition(data);
  if (!result.status) throwLedgerError({});
  return result;
}

export function creditLedger(
  admin: Admin,
  charge: ChargeRow,
): Promise<TransitionResult> {
  return applyPaymentTransition(admin, charge.id, "paid", true);
}

export function reverseLedger(
  admin: Admin,
  charge: ChargeRow,
): Promise<TransitionResult> {
  return applyPaymentTransition(admin, charge.id, "refunded", false);
}
