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
  const { data, error } = await admin.rpc("claim_payment_reconciliation");
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
    return await releaseClaim(admin, row);
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
  return await releaseClaim(admin, row);
}

async function reconcileOrphan(
  admin: Admin,
  asaas: AsaasProvider,
  row: OrphanRow,
): Promise<boolean> {
  if (!row.provider_ref) return false;
  let remote: RemotePayment | null = null;
  try {
    remote = await asaas.getPayment(row.provider_ref);
  } catch (error) {
    if (!isMissing(error)) return false;
    return await finishOrphan(admin, row, "cancelled");
  }
  if (!remote || remote.id !== row.provider_ref) return false;
  const action = lostAttemptCompensation(remote.status);
  if (action === "none") {
    const next = remote.status.trim().toUpperCase() === "REFUNDED"
      ? "refunded"
      : "cancelled";
    return await finishOrphan(admin, row, next);
  }
  const gone = await releaseRemote(
    asaas,
    row.provider_ref,
    remote.status,
    remote.billingType || row.billing_type,
  );
  if (!gone) return false;
  return await finishOrphan(
    admin,
    row,
    action === "refund" ? "refunded" : "cancelled",
  );
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

/// A transição só vale para este attempt e este provider_ref. Erro ou
/// attempt divergente não marca o órfão. Cobrança de outro pagamento
/// (skipped) pode ser encerrada.
async function finishOrphan(
  admin: Admin,
  row: OrphanRow,
  nextStatus: "cancelled" | "refunded",
): Promise<boolean> {
  if (row.charge_id) {
    const settled = await settleStuckCharge(admin, row, nextStatus);
    if (settled !== "done") return false;
  }
  return await markResolved(admin, row.id);
}

async function settleStuckCharge(
  admin: Admin,
  row: OrphanRow,
  nextStatus: "cancelled" | "refunded",
): Promise<"done" | "blocked"> {
  const { data, error } = await admin.rpc("settle_orphan_charge", {
    p_charge_id: row.charge_id,
    p_attempt_id: row.attempt_id,
    p_provider_ref: row.provider_ref,
    p_next_status: nextStatus,
  });
  if (error) return "blocked";
  const record = data && typeof data === "object"
    ? data as { skipped?: unknown; status?: unknown }
    : {};
  if (record.skipped === true) return "done";
  return String(record.status ?? "") === nextStatus ? "done" : "blocked";
}

async function releaseClaim(admin: Admin, row: CreatingRow): Promise<boolean> {
  const { data, error } = await admin.rpc("release_pix_reservation", {
    p_charge_id: row.charge_id,
    p_attempt_id: row.attempt_id,
  });
  return !error && data === true;
}

async function markResolved(admin: Admin, id: string): Promise<boolean> {
  const { data, error } = await admin.rpc("mark_orphan_resolved", {
    p_id: id,
  });
  return !error && data === true;
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
