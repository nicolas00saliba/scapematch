import { logCaught } from "./client_error.ts";
import { type ChargeRow } from "./ledger.ts";
import { bandConfirmed, bandMissed, bandSettlement } from "./group_band.ts";
import { isAlternateProvider, isHistoricalAsaas } from "./payment_provider.ts";
import {
  settleAlternateCharge,
  type AlternateGate,
} from "./provider_dispatch.ts";
import { releaseCancelledCharges } from "./release_charges.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

const claimMissing = new Set(["PGRST202", "42883"]);

type GroupRow = {
  id: string;
  created_by?: string;
  venue_id?: string;
  cancelled_at: string | null;
  confirmed_at?: string | null;
  closed_at: string | null;
  closes_at: string | null;
  total_spots: number;
  minimum_spots: number;
};

type ChargeView = ChargeRow & {
  status: string;
  provider?: string | null;
  provider_ref: string | null;
  billing_type: string;
  provider_end_to_end_id?: string | null;
  house_pix_key?: string | null;
  house_fixed_cents?: number | null;
};

/// Admin, criador e dono da casa liquidam ou liberam.
/// Quem só está no grupo liquida quando ele confirma. Não estorna grupo aberto.
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
      "created_by, venue_id, cancelled_at, confirmed_at, closed_at, closes_at, total_spots, minimum_spots",
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
  const filled = await filledSpots(admin, groupId);
  return bandConfirmed(group, filled);
}

export async function settleGroup(
  admin: Admin,
  groupId: string,
  gate?: AlternateGate,
): Promise<void> {
  const { data: group } = await admin
    .from("groups")
    .select(
      "id, cancelled_at, confirmed_at, closed_at, closes_at, starts_at, total_spots, minimum_spots",
    )
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return;
  const row = group as GroupRow;
  const filled = await filledSpots(admin, groupId);
  const decision = bandSettlement(row, filled);
  if (decision === "release") {
    if (bandMissed(row, filled)) {
      await admin
        .from("groups")
        .update({
          cancelled_at: new Date().toISOString(),
          cancel_reason: "O grupo não confirmou a tempo",
        })
        .eq("id", groupId)
        .is("cancelled_at", null)
        .is("confirmed_at", null);
    }
    await releaseCancelledCharges(admin, groupId, gate);
    return;
  }
  if (decision === "wait") return;

  // commission_bps é a taxa fotografada na cobrança por create-charge.
  const { data: charges } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, provider, provider_ref, billing_type, provider_end_to_end_id, house_pix_key, house_fixed_cents",
    )
    .eq("group_id", groupId);

  for (const charge of charges ?? []) {
    const item = charge as ChargeView;
    if (isHistoricalAsaas(item.provider)) continue;
    if (isAlternateProvider(item.provider)) {
      if (item.status === "authorized" || item.status === "paid") {
        await settleAlternateCharge(admin, item, gate);
      }
    }
  }
}

/// Cancela no banco os grupos cujo prazo venceu sem confirmação.
/// O cron libera as cobranças desses ids em seguida.
export async function expireUnconfirmedGroups(admin: Admin): Promise<string[]> {
  if (typeof admin?.rpc !== "function") return [];
  const { data, error } = await admin.rpc("expire_unconfirmed_groups");
  if (error) {
    if (!claimMissing.has(error.code)) logCaught("settle-charges", error);
    return [];
  }
  if (!Array.isArray(data)) return [];
  return data.filter((id): id is string =>
    typeof id === "string" && id.length > 0
  );
}

/// Varre autorizações ainda abertas. O cron de reconcile chama isto.
/// Um grupo que falha não impede o próximo.
export async function settleAuthorizedCards(
  admin: Admin,
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
      await settleGroup(admin, id);
    } catch (error) {
      logCaught("settle-charges", error);
    }
  }
}

async function filledSpots(admin: Admin, groupId: string): Promise<number> {
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return count ?? 0;
}
