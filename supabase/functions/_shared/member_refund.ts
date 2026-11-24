// Estorno de um jogador que saiu no prazo ou foi removido.
// A fila nasce na SQL. Este módulo fala com a PagBank.
// refunded no membro só depois da transição da cobrança.
//
// HELD: não solta a custódia. O cancelamento devolve o saldo retido.
// Custódia já liberada: o mesmo estorno, pelo total cobrado (com juros),
// desfaz a parte da casa e a da EscapeMatch na PagBank. Sem transferência
// extra. Falha da PagBank deixa a fila aberta.

import { logCaught } from "./pagbank_client_error.ts";
import { captureAmountCents } from "./pagbank_rules.ts";
import { applyPaymentTransition } from "./ledger.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export const maxMemberRefundAttempts = 8;

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
  status: string;
  attempts: number;
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
  if (typeof admin?.from !== "function") return { done: 0, pending: 0 };
  let query = admin
    .from("member_refund_queue")
    .select("id, charge_id, group_id, user_id, action, status, attempts")
    .eq("status", "queued")
    .lt("attempts", maxMemberRefundAttempts);
  const groupId = filter?.groupId ?? "";
  const userId = filter?.userId ?? "";
  if (groupId) query = query.eq("group_id", groupId);
  if (userId) query = query.eq("user_id", userId);
  const { data, error } = await query
    .order("created_at", { ascending: true })
    .limit(20);
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

async function refundOne(
  admin: Admin,
  pagbank: RefundClient,
  row: QueueRow,
): Promise<boolean> {
  const claimed = await admin
    .from("member_refund_queue")
    .update({ attempts: row.attempts + 1 })
    .eq("id", row.id)
    .eq("status", "queued")
    .eq("attempts", row.attempts)
    .select("id");
  if (claimed.error || !Array.isArray(claimed.data) || claimed.data.length === 0) {
    return false;
  }
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
    const next = await moveRemote(pagbank, charge, ref, remote.status);
    if (!next) return false;
    const transition = await applyPaymentTransition(admin, charge.id, next, false);
    if (transition.status !== "refunded" && transition.status !== "cancelled") {
      return false;
    }
    const finished = await admin
      .from("member_refund_queue")
      .update({ status: "done", done_at: new Date().toISOString() })
      .eq("id", row.id)
      .eq("status", "queued")
      .select("id");
    return !finished.error && Array.isArray(finished.data) &&
      finished.data.length > 0;
  } catch (error) {
    logCaught("member_refund", error);
    if (row.attempts + 1 >= maxMemberRefundAttempts) {
      logCaught("member_refund_exhausted", error);
    }
    return false;
  }
}

/// null = a PagBank ainda não confirmou. Não marca refunded.
async function moveRemote(
  pagbank: RefundClient,
  charge: Charge,
  ref: string,
  remoteStatus: string,
): Promise<"refunded" | "cancelled" | null> {
  const kind = remoteKind(remoteStatus);
  if (kind === "refunded") return "refunded";
  if (kind === "cancelled") return "cancelled";
  const cents = captureAmountCents(charge);
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
