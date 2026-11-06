import { asaasPaymentGone, AsaasProvider } from "./asaas_provider.ts";
import { detachGonePix } from "./detach_gone_pix.ts";
import { lostAttemptCompensation, pixLeaseMs } from "./pix_charge.ts";

/// Cada chamada ao Asaas cabe várias vezes dentro do lease de 2 minutos.
export const reconcileAsaasTimeoutMs = 8_000;

if (reconcileAsaasTimeoutMs * 4 >= pixLeaseMs) {
  throw new Error("timeout do Asaas perto do lease");
}

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
  claimed_at: string | null;
};

type Gate = "owned" | "lost" | "error";
type RemoteOutcome = "gone" | "failed" | "lost";

type RemotePayment = {
  id: string;
  status: string;
  billingType: string;
  deleted?: boolean;
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
  let remote: RemotePayment | null = null;
  try {
    remote = row.external_reference
      ? await asaas.findByExternalReference(row.external_reference)
      : null;
  } catch (_error) {
    return false;
  }
  if (!remote) {
    return await releaseClaim(admin, row);
  }
  const outcome = await releaseRemote(
    asaas,
    remote.id,
    remote.status,
    remote.billingType || row.billing_type,
    () => confirmCreating(admin, row),
  );
  if (outcome === "lost") return true;
  if (outcome === "failed") {
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
  if (remote.deleted === true || asaasPaymentGone(remote)) {
    if (
      row.charge_id &&
      (row.billing_type === "PIX" || remote.billingType === "PIX") &&
      remote.status.trim().toUpperCase() !== "REFUNDED"
    ) {
      try {
        await detachGonePix(admin, row.charge_id, row.provider_ref);
      } catch (_error) {
        return false;
      }
    }
    const next = remote.status.trim().toUpperCase() === "REFUNDED"
      ? "refunded"
      : "cancelled";
    return await finishOrphan(admin, row, next);
  }
  const action = lostAttemptCompensation(remote.status);
  if (action === "none") {
    const next = remote.status.trim().toUpperCase() === "REFUNDED"
      ? "refunded"
      : "cancelled";
    return await finishOrphan(admin, row, next);
  }
  const outcome = await releaseRemote(
    asaas,
    row.provider_ref,
    remote.status,
    remote.billingType || row.billing_type,
    () => confirmOrphan(admin, row),
  );
  if (outcome !== "gone") return false;
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
  confirm: () => Promise<Gate>,
): Promise<RemoteOutcome> {
  const action = lostAttemptCompensation(status);
  if (action === "none") return "gone";
  const gate = await confirm();
  if (gate !== "owned") return gate === "lost" ? "lost" : "failed";
  try {
    if (billingType === "PIX" && action === "cancel") {
      const gone = await asaas.cancelPaymentConfirmed(paymentId);
      return gone ? "gone" : "failed";
    }
    if (action === "refund") await asaas.refund(paymentId);
    else await asaas.cancelAuthorization(paymentId);
    return "gone";
  } catch (_error) {
    return "failed";
  }
}

async function confirmCreating(admin: Admin, row: CreatingRow): Promise<Gate> {
  if (!row.attempt_id) return "lost";
  const { data, error } = await admin.rpc("confirm_reconcile_claim", {
    p_charge_id: row.charge_id,
    p_attempt_id: row.attempt_id,
  });
  if (error) return "error";
  return data === true ? "owned" : "lost";
}

async function confirmOrphan(admin: Admin, row: OrphanRow): Promise<Gate> {
  if (!row.claimed_at) return "lost";
  const { data, error } = await admin.rpc("confirm_orphan_claim", {
    p_id: row.id,
    p_claimed_at: row.claimed_at,
  });
  if (error) return "error";
  return data === true ? "owned" : "lost";
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
