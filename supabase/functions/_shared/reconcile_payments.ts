import { AsaasProvider } from "./asaas_provider.ts";
import { lostAttemptCompensation } from "./pix_charge.ts";

type CreatingRow = {
  charge_id: string;
  attempt_id: string | null;
  billing_type: string;
  external_reference: string;
};

type OrphanRow = {
  id: string;
  provider_ref: string;
  charge_id: string | null;
  attempt_id: string | null;
  billing_type: string;
  external_reference: string | null;
};

type RemotePayment = {
  id: string;
  status: string;
  billingType: string;
};

// deno-lint-ignore no-explicit-any
type Admin = any;

export async function reconcilePayments(
  admin: Admin,
  asaas: AsaasProvider,
): Promise<{ resolved: number; pending: number }> {
  const { data, error } = await admin.rpc("list_payment_reconciliation");
  if (error) throw new Error("erro");
  const work = asWork(data);
  let resolved = 0;
  let pending = 0;
  for (const row of work.creating) {
    if (await reconcileCreating(admin, asaas, row)) resolved += 1;
    else pending += 1;
  }
  for (const row of work.orphans) {
    if (await reconcileOrphan(admin, asaas, row)) resolved += 1;
    else pending += 1;
  }
  return { resolved, pending };
}

async function reconcileCreating(
  admin: Admin,
  asaas: AsaasProvider,
  row: CreatingRow,
): Promise<boolean> {
  const remote = row.external_reference
    ? await asaas.findByExternalReference(row.external_reference)
    : null;
  if (!remote) {
    const { data, error } = await admin.rpc("release_expired_pix_reservation", {
      p_charge_id: row.charge_id,
      p_attempt_id: row.attempt_id,
    });
    return !error && data === true;
  }
  const gone = await releaseRemote(
    asaas,
    remote.id,
    remote.status,
    remote.billingType || row.billing_type,
  );
  if (!gone) {
    const action = lostAttemptCompensation(remote.status);
    await admin.rpc("record_orphan_payment", {
      p_provider_ref: remote.id,
      p_charge_id: row.charge_id,
      p_attempt_id: row.attempt_id,
      p_billing_type: remote.billingType || row.billing_type,
      p_reason: action === "refund" ? "refund_failed" : "cancel_failed",
    });
    return false;
  }
  await admin.rpc("release_expired_pix_reservation", {
    p_charge_id: row.charge_id,
    p_attempt_id: row.attempt_id,
  });
  return true;
}

async function reconcileOrphan(
  admin: Admin,
  asaas: AsaasProvider,
  row: OrphanRow,
): Promise<boolean> {
  let remote: RemotePayment | null = null;
  if (row.external_reference) {
    remote = await asaas.findByExternalReference(row.external_reference);
  }
  if (!remote && row.provider_ref) {
    try {
      remote = await asaas.getPayment(row.provider_ref);
    } catch (error) {
      if (!isMissing(error)) return false;
      if (!(await settleStuckCharge(admin, row, "cancelled"))) return false;
      return await markResolved(admin, row.id);
    }
  }
  if (!remote) {
    if (!(await settleStuckCharge(admin, row, "cancelled"))) return false;
    return await markResolved(admin, row.id);
  }
  const action = lostAttemptCompensation(remote.status);
  if (action === "none") {
    const next = remote.status.trim().toUpperCase() === "REFUNDED"
      ? "refunded"
      : "cancelled";
    if (!(await settleStuckCharge(admin, row, next))) return false;
    return await markResolved(admin, row.id);
  }
  const gone = await releaseRemote(
    asaas,
    remote.id,
    remote.status,
    remote.billingType || row.billing_type,
  );
  if (!gone) return false;
  if (row.charge_id) {
    await admin.rpc("apply_payment_transition", {
      p_charge_id: row.charge_id,
      p_next_status: action === "refund" ? "refunded" : "cancelled",
      p_credit: false,
    });
  }
  return await markResolved(admin, row.id);
}

async function releaseRemote(
  asaas: AsaasProvider,
  paymentId: string,
  status: string,
  billingType: string,
): Promise<boolean> {
  const action = lostAttemptCompensation(status);
  if (action === "none") return true;
  try {
    if (billingType === "PIX" && action === "cancel") {
      return await asaas.cancelPaymentConfirmed(paymentId);
    }
    if (action === "refund") await asaas.refund(paymentId);
    else await asaas.cancelAuthorization(paymentId);
    return true;
  } catch (_error) {
    return false;
  }
}

/// Cobrança presa em creating/authorized, com o mesmo id do Asaas, sai
/// para cancelled ou refunded antes de o órfão ser marcado. Outro
/// provider_ref, ou status já terminal, não é mexido.
async function settleStuckCharge(
  admin: Admin,
  row: OrphanRow,
  nextStatus: "cancelled" | "refunded",
): Promise<boolean> {
  if (!row.charge_id || !row.provider_ref) return true;
  const { data, error } = await admin
    .from("payment_charges")
    .select("status, provider_ref")
    .eq("id", row.charge_id)
    .maybeSingle();
  if (error) return false;
  const charge = data as
    | { status?: string; provider_ref?: string | null }
    | null;
  if (!charge) return true;
  const stuck = charge.status === "creating" || charge.status === "authorized";
  if (!stuck || charge.provider_ref !== row.provider_ref) return true;
  const { data: transition, error: transitionError } = await admin.rpc(
    "apply_payment_transition",
    {
      p_charge_id: row.charge_id,
      p_next_status: nextStatus,
      p_credit: false,
    },
  );
  if (transitionError) return false;
  const status = transition && typeof transition === "object"
    ? String((transition as { status?: unknown }).status ?? "")
    : "";
  return status === nextStatus;
}

async function markResolved(admin: Admin, id: string): Promise<boolean> {
  const { error } = await admin.rpc("mark_orphan_resolved", { p_id: id });
  return !error;
}

function asWork(
  data: unknown,
): { creating: CreatingRow[]; orphans: OrphanRow[] } {
  const record = data && typeof data === "object"
    ? data as Record<string, unknown>
    : {};
  return {
    creating: Array.isArray(record.creating)
      ? record.creating as CreatingRow[]
      : [],
    orphans: Array.isArray(record.orphans) ? record.orphans as OrphanRow[] : [],
  };
}

function isMissing(error: unknown): boolean {
  const raw = error instanceof Error ? error.message : "";
  return raw.startsWith("Asaas 404");
}
