import { logCaught } from "./asaas_client_error.ts";
import { asaasPaymentGone, AsaasProvider } from "./asaas_provider.ts";
import { issuePaidInvoices } from "./issue_invoices.ts";
import {
  applyPaymentTransition,
  type ChargeRow,
  creditLedger,
} from "./ledger.ts";
import { syncPayerDocument } from "./payer_document.ts";
import { releaseCancelledCharges } from "./release_charges.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

const claimMissing = new Set(["PGRST202", "42883"]);

type GroupRow = {
  id: string;
  created_by?: string;
  venue_id?: string;
  cancelled_at: string | null;
  closed_at: string | null;
  closes_at: string | null;
  total_spots: number;
  minimum_spots: number;
};

type ChargeView = ChargeRow & {
  status: string;
  provider_ref: string | null;
  billing_type: string;
};

/// Admin, criador e dono da casa liquidam ou liberam.
/// Quem só está no grupo liquida quando ele já fechou. Não estorna grupo aberto.
export async function maySettle(
  admin: Admin,
  groupId: string,
  userId: string,
  isAdmin: boolean,
): Promise<boolean> {
  if (isAdmin) return true;
  const { data: group } = await admin
    .from("groups")
    .select(
      "created_by, venue_id, cancelled_at, closed_at, total_spots, minimum_spots",
    )
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return false;
  if (group.created_by === userId) return true;
  const { data: venue } = await admin
    .from("venues")
    .select("owner_id")
    .eq("id", group.venue_id)
    .maybeSingle();
  if (venue?.owner_id === userId) return true;
  if (group.cancelled_at) return false;
  const { data: member } = await admin
    .from("group_members")
    .select("attendance")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .maybeSingle();
  if (!member || member.attendance === "cancelled") return false;
  if (group.closed_at) return true;
  const filled = await filledSpots(admin, groupId);
  return filled >= group.total_spots && filled >= group.minimum_spots;
}

export async function settleGroup(
  admin: Admin,
  asaas: AsaasProvider,
  groupId: string,
): Promise<void> {
  const { data: group } = await admin
    .from("groups")
    .select(
      "id, cancelled_at, closed_at, closes_at, starts_at, total_spots, minimum_spots",
    )
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return;
  const row = group as GroupRow;
  const filled = await filledSpots(admin, groupId);
  const closed = Boolean(row.closed_at) ||
    (filled >= row.total_spots && filled >= row.minimum_spots);
  const missed = !row.cancelled_at && !closed && row.closes_at &&
    new Date(row.closes_at).getTime() <= Date.now() &&
    filled < row.minimum_spots;
  const release = Boolean(row.cancelled_at) || missed;
  if (release) {
    await releaseCancelledCharges(admin, asaas, groupId);
    return;
  }
  if (!closed) return;

  // commission_bps é a taxa fotografada na cobrança por create-charge.
  const { data: charges } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, provider_ref, billing_type",
    )
    .eq("group_id", groupId);

  for (const charge of charges ?? []) {
    const item = charge as ChargeView;
    if (!item.provider_ref) continue;
    if (item.status === "authorized" && item.billing_type === "CREDIT_CARD") {
      await captureAuthorizedCard(admin, asaas, item);
      continue;
    }
    if (item.status === "paid") {
      await syncPayerDocument(admin, asaas, {
        id: item.id,
        user_id: item.user_id,
        billing_type: item.billing_type,
        provider_ref: item.provider_ref,
      });
      await creditLedger(admin, item);
      await issuePaidInvoices(admin, item, {
        sandbox: asaas.sandbox,
        asaas: asaas.sandbox ? undefined : asaas,
      });
    }
  }
}

/// Varre autorizações ainda abertas. O cron de reconcile chama isto.
/// Um grupo que falha não impede o próximo.
export async function settleAuthorizedCards(
  admin: Admin,
  asaas: AsaasProvider,
): Promise<void> {
  if (typeof admin?.from !== "function") return;
  const { data, error } = await admin
    .from("payment_charges")
    .select("group_id")
    .eq("status", "authorized")
    .eq("billing_type", "CREDIT_CARD")
    .limit(40);
  if (error || !Array.isArray(data)) return;
  const ids = new Set<string>();
  for (const row of data) {
    const id = (row as { group_id?: unknown }).group_id;
    if (typeof id === "string" && id.length > 0) ids.add(id);
  }
  for (const id of ids) {
    try {
      await settleGroup(admin, asaas, id);
    } catch (error) {
      logCaught("settle-charges", error);
    }
  }
}

async function captureAuthorizedCard(
  admin: Admin,
  asaas: AsaasProvider,
  row: ChargeView,
): Promise<void> {
  if (!row.provider_ref) return;
  const claimed = await claimCardCapture(admin, row.id);
  if (!claimed) return;
  try {
    const remote = await asaas.getPayment(row.provider_ref);
    if (asaasPaymentGone(remote)) {
      await releaseCardCaptureClaim(admin, row.id);
      const transition = await applyPaymentTransition(
        admin,
        row.id,
        goneProviderLocalStatus(remote.status),
        false,
      );
      if (transition.status === "authorized") throw new Error("erro");
      return;
    }
    const already = remote.status === "CONFIRMED" ||
      remote.status === "RECEIVED";
    let paid = already;
    if (!already) {
      const captured = await asaas.capture(row.provider_ref);
      paid = captured.status === "CONFIRMED" || captured.status === "RECEIVED";
    }
    if (!paid) {
      await releaseCardCaptureClaim(admin, row.id);
      return;
    }
    const transition = await applyPaymentTransition(
      admin,
      row.id,
      "paid",
      true,
    );
    if (transition.status !== "paid") return;
    await issuePaidInvoices(admin, row, {
      sandbox: asaas.sandbox,
      asaas: asaas.sandbox ? undefined : asaas,
    });
  } catch (error) {
    await releaseCardCaptureClaim(admin, row.id);
    throw error;
  }
}

/// REFUNDED vira estorno. deleted, CANCELED e CANCELLED viram cancelamento.
/// O membro sai de reserved/paid e fica released pela transição do ledger.
export function goneProviderLocalStatus(
  status: string,
): "refunded" | "cancelled" {
  return status.trim().toUpperCase() === "REFUNDED" ? "refunded" : "cancelled";
}

/// Sem a função no banco, segue em frente: a leitura do status no Asaas
/// evita uma segunda captura na tentativa seguinte.
async function claimCardCapture(
  admin: Admin,
  chargeId: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("claim_card_capture", {
    p_charge_id: chargeId,
  });
  if (error) {
    const code = typeof error.code === "string" ? error.code : "";
    if (claimMissing.has(code)) return true;
    throw new Error("erro");
  }
  return data === true;
}

async function releaseCardCaptureClaim(
  admin: Admin,
  chargeId: string,
): Promise<void> {
  const { error } = await admin.rpc("release_card_capture_claim", {
    p_charge_id: chargeId,
  });
  if (!error) return;
  const code = typeof error.code === "string" ? error.code : "";
  if (claimMissing.has(code)) return;
  throw new Error("erro");
}

async function filledSpots(admin: Admin, groupId: string): Promise<number> {
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return count ?? 0;
}
