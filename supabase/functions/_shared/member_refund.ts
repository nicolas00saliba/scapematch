// Estorno de um jogador que saiu no prazo ou foi removido.
// A fila nasce na SQL. Este módulo fala com a PagBank.
// refunded no membro só depois da transição da cobrança.
//
// HELD: não solta a custódia. O cancelamento devolve o saldo retido.
// Custódia já liberada: o estorno usa o valor da fila. Esse valor já
// descontou a taxa PagBank da cobrança. Sem a fila, vale o total cobrado.
// Valor zero não chama a PagBank: um cancelamento sem valor devolveria
// a cobrança inteira. Falha da PagBank deixa a fila aberta.

import { logCaught } from "./pagbank_client_error.ts";
import { captureAmountCents } from "./pagbank_rules.ts";
import { applyPaymentTransition } from "./ledger.ts";
import { reconcilePagBankTimeoutMs } from "./reconcile_payments.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export const maxMemberRefundAttempts = 8;

/// Igual ao interval '90 seconds' de claim_member_refunds.
export const memberRefundLeaseMs = 90_000;

if (reconcilePagBankTimeoutMs * 4 >= memberRefundLeaseMs) {
  throw new Error("timeout do PagBank perto do lease do estorno");
}

type RefundClient = {
  getPayment(id: string): Promise<{ status: string }>;
  refund(id: string, amountCents: number): Promise<{ status: string }>;
  cancelAuthorization(
    id: string,
    amountCents: number,
  ): Promise<{ status: string }>;
  cancelPaymentConfirmed(id: string): Promise<boolean>;
};

type QueueRow = {
  id: string;
  charge_id: string;
  group_id: string;
  user_id: string;
  action: string;
  amount_cents?: number | null;
  status: string;
  attempts: number;
  lease_until?: string | null;
};

type Charge = {
  id: string;
  amount_cents: number;
  charged_amount_cents?: number | null;
  status: string;
  provider_ref: string | null;
  billing_type: string;
  custody_released_at?: string | null;
  refund_requested_at?: string | null;
};

export type MemberRefundResult = { done: number; pending: number };

/// Quem pode disparar a fila: admin, criador, dono da casa, ou o próprio
/// jogador. Jogador só processa a cobrança dele.
export async function memberRefundActor(
  admin: Admin,
  groupId: string,
  userId: string,
  isAdmin: boolean,
): Promise<{ userId?: string } | null> {
  if (!groupId || !userId) return null;
  if (isAdmin) return {};
  const { data: group } = await admin
    .from("groups")
    .select("created_by, venue_id")
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return null;
  if (group.created_by === userId) return {};
  const { data: venue } = await admin
    .from("venues")
    .select("owner_id")
    .eq("id", group.venue_id)
    .maybeSingle();
  if (venue?.owner_id === userId) return {};
  const { data: member } = await admin
    .from("group_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .maybeSingle();
  if (!member) return null;
  return { userId };
}

export async function processMemberRefunds(
  admin: Admin,
  pagbank: RefundClient,
  filter?: { groupId?: string; userId?: string },
): Promise<MemberRefundResult> {
  if (typeof admin?.rpc !== "function") return { done: 0, pending: 0 };
  const groupId = filter?.groupId ?? "";
  const userId = filter?.userId ?? "";
  const { data, error } = await admin.rpc("claim_member_refunds", {
    p_limit: 20,
    p_group_id: groupId || null,
    p_user_id: userId || null,
  });
  if (error || !Array.isArray(data)) return { done: 0, pending: 0 };

  let done = 0;
  let pending = 0;
  for (const item of data as QueueRow[]) {
    const closed = await refundOne(admin, pagbank, item);
    if (closed) done += 1;
    else pending += 1;
  }
  return { done, pending };
}

function leaseOpen(row: QueueRow, now = Date.now()): boolean {
  const until = Date.parse(row.lease_until ?? "");
  return Number.isFinite(until) && until > now;
}

async function refundOne(
  admin: Admin,
  pagbank: RefundClient,
  row: QueueRow,
): Promise<boolean> {
  try {
    const { data, error } = await admin
      .from("payment_charges")
      .select(
        "id, amount_cents, charged_amount_cents, status, provider_ref, billing_type, custody_released_at, refund_requested_at",
      )
      .eq("id", row.charge_id)
      .maybeSingle();
    if (error || !data) throw new Error("erro");
    const charge = data as Charge;
    const ref = (charge.provider_ref ?? "").trim();
    if (!ref) throw new Error("erro");
    const remote = await pagbank.getPayment(ref);
    const kind = remoteKind(remote.status);
    // Timeout com a cobrança ainda paga: não reenvia neste lease.
    // O próximo claim só existe depois que o prazo volta a fila.
    if (kind !== "refunded" && kind !== "cancelled" && !leaseOpen(row)) {
      return false;
    }
    const cents = queuedCents(row, charge);
    if (cents <= 0) return false;
    const next = await moveRemote(pagbank, charge, ref, remote.status, cents);
    if (!next) return false;
    const transition = await applyPaymentTransition(admin, charge.id, next, false);
    if (transition.status !== "refunded" && transition.status !== "cancelled") {
      return false;
    }
    const finished = await admin
      .from("member_refund_queue")
      .update({
        status: "done",
        done_at: new Date().toISOString(),
        lease_until: null,
      })
      .eq("id", row.id)
      .eq("status", "processing")
      .eq("lease_until", row.lease_until ?? "")
      .select("id");
    return !finished.error && Array.isArray(finished.data) &&
      finished.data.length > 0;
  } catch (error) {
    logCaught("member_refund", error);
    if (row.attempts >= maxMemberRefundAttempts) {
      logCaught("member_refund_exhausted", error);
    }
    return false;
  }
}

function queuedCents(row: QueueRow, charge: Charge): number {
  const queued = row.amount_cents;
  if (typeof queued === "number" && Number.isInteger(queued) && queued >= 0) {
    return queued;
  }
  return captureAmountCents(charge);
}

/// null = a PagBank ainda não confirmou. Não marca refunded.
async function moveRemote(
  pagbank: RefundClient,
  charge: Charge,
  ref: string,
  remoteStatus: string,
  cents: number,
): Promise<"refunded" | "cancelled" | null> {
  const kind = remoteKind(remoteStatus);
  if (kind === "refunded") return "refunded";
  if (kind === "cancelled") return "cancelled";
  if (kind === "paid") {
    const refunded = await pagbank.refund(ref, cents);
    return remoteKind(refunded.status) === "refunded" ? "refunded" : null;
  }
  if (kind !== "open") return null;
  if ((charge.billing_type ?? "").toUpperCase() === "PIX") {
    const gone = await pagbank.cancelPaymentConfirmed(ref);
    return gone ? "cancelled" : null;
  }
  const voided = await pagbank.cancelAuthorization(ref, cents);
  return remoteKind(voided.status) === "cancelled" ? "cancelled" : null;
}

function remoteKind(
  status: string,
): "paid" | "open" | "refunded" | "cancelled" | "unknown" {
  switch (status.trim().toUpperCase()) {
    case "REFUNDED":
      return "refunded";
    case "CANCELED":
    case "CANCELLED":
    case "DELETED":
    case "DECLINED":
      return "cancelled";
    case "PAID":
    case "CONFIRMED":
    case "RECEIVED":
      return "paid";
    case "AUTHORIZED":
    case "PENDING":
    case "WAITING":
    case "IN_ANALYSIS":
      return "open";
    default:
      return "unknown";
  }
}
