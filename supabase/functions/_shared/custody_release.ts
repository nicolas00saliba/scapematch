// Solta a custódia HELD depois que o grupo confirma.
// Falha fica na cobrança e o cron tenta de novo.

import { logCaught } from "./pagbank_client_error.ts";
import { bandConfirmed } from "./group_band.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type CustodyClient = {
  releaseCustody(splitId: string, accountIds: string[]): Promise<void>;
};

export type CustodyCharge = {
  id: string;
  provider_split_id?: string | null;
  custody_released_at?: string | null;
};

export async function rememberSplitId(
  admin: Admin,
  chargeId: string,
  splitId: string | null | undefined,
): Promise<void> {
  const id = (splitId ?? "").trim();
  if (!id || !chargeId) return;
  const { error } = await admin.from("payment_charges").update({
    provider_split_id: id,
  }).eq("id", chargeId);
  if (error) logCaught("custody-release", error);
}

/// Cartão capturado com o grupo já confirmado solta a custódia.
/// Sem confirmação, só grava o splitId para o acerto soltar depois.
export async function finishCapturedCard(input: {
  admin: Admin;
  pagbank: CustodyClient;
  chargeId: string;
  splitId: string | null | undefined;
  paid: boolean;
}): Promise<void> {
  await rememberSplitId(input.admin, input.chargeId, input.splitId);
  if (!input.paid) return;
  await releaseHeldSplit(input.admin, input.pagbank, {
    id: input.chargeId,
    provider_split_id: input.splitId,
  });
}

/// Pix pago com o grupo já confirmado. Grupo aberto continua em custódia.
export async function releasePaidIfClosed(input: {
  admin: Admin;
  pagbank: CustodyClient;
  charge: CustodyCharge;
  groupClosed: boolean;
}): Promise<void> {
  if (!input.groupClosed) return;
  if (input.charge.custody_released_at) return;
  await releaseHeldSplit(input.admin, input.pagbank, input.charge);
}

export async function releaseHeldSplit(
  admin: Admin,
  pagbank: CustodyClient,
  charge: CustodyCharge,
): Promise<boolean> {
  const id = (charge.provider_split_id ?? "").trim();
  if (!id || !charge.id || charge.custody_released_at) return false;
  try {
    await pagbank.releaseCustody(id, []);
    const { error } = await admin.from("payment_charges").update({
      custody_released_at: new Date().toISOString(),
      custody_release_failed_at: null,
    }).eq("id", charge.id);
    if (error) logCaught("custody-release", error);
    return true;
  } catch (error) {
    const failed = await admin.from("payment_charges").update({
      custody_release_failed_at: new Date().toISOString(),
    }).eq("id", charge.id);
    if (failed.error) logCaught("custody-release", failed.error);
    logCaught("custody_release_failed", error);
    return false;
  }
}

/// Cobrança paga, com split, ainda sem custódia solta. O cron chama isto.
export async function retryPendingCustodyReleases(
  admin: Admin,
  pagbank: CustodyClient,
): Promise<number> {
  if (typeof admin?.from !== "function") return 0;
  const { data, error } = await admin
    .from("payment_charges")
    .select("id, group_id, provider_split_id, status, custody_released_at")
    .eq("status", "paid")
    .is("custody_released_at", null)
    .not("provider_split_id", "is", null)
    .limit(40);
  if (error || !Array.isArray(data)) return 0;
  let released = 0;
  for (const row of data) {
    const charge = row as CustodyCharge & { group_id?: string };
    if (!charge.group_id) continue;
    if (!await groupIsClosed(admin, charge.group_id)) continue;
    if (await releaseHeldSplit(admin, pagbank, charge)) released += 1;
  }
  return released;
}

async function groupIsClosed(admin: Admin, groupId: string): Promise<boolean> {
  const { data: group } = await admin
    .from("groups")
    .select(
      "cancelled_at, confirmed_at, closed_at, closes_at, total_spots, minimum_spots",
    )
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return false;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return bandConfirmed(group, count ?? 0);
}
