// Solta a custódia HELD depois que o grupo confirma.
// Falha fica na cobrança e o cron tenta de novo.

import { logCaught } from "./pagbank_client_error.ts";
import { bandConfirmed } from "./group_band.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type CustodyClient = {
  releaseCustody(splitId: string, accountIds: string[]): Promise<void>;
  accountId(): string;
};

export type CustodyCharge = {
  id: string;
  venue_id?: string | null;
  provider_split_id?: string | null;
  custody_released_at?: string | null;
  custody_release_attempts?: number | null;
  created_at?: string | null;
};

/// Depois disto o cron para e o log custody_release_exhausted alerta.
export const maxCustodyReleaseAttempts = 8;

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
    const accounts = await custodyAccountIds(admin, pagbank, charge);
    if (accounts.length === 0) throw new Error("custodia_recebedores");
    await pagbank.releaseCustody(id, accounts);
    const { error } = await admin.from("payment_charges").update({
      custody_released_at: new Date().toISOString(),
      custody_release_failed_at: null,
    }).eq("id", charge.id);
    if (error) logCaught("custody-release", error);
    return true;
  } catch (error) {
    const attempts = nextCustodyAttempt(charge.custody_release_attempts);
    const failed = await admin.from("payment_charges").update({
      custody_release_failed_at: new Date().toISOString(),
      custody_release_attempts: attempts,
    }).eq("id", charge.id);
    if (failed.error) logCaught("custody-release", failed.error);
    logCaught("custody_release_failed", error);
    if (attempts >= maxCustodyReleaseAttempts) {
      logCaught("custody_release_exhausted", error);
    }
    return false;
  }
}

/// Casa e EscapeMatch, como no exemplo de POST /splits/{id}/custody/release.
async function custodyAccountIds(
  admin: Admin,
  pagbank: CustodyClient,
  charge: CustodyCharge,
): Promise<string[]> {
  let venueId = (charge.venue_id ?? "").trim();
  if (!venueId) {
    const { data } = await admin
      .from("payment_charges")
      .select("venue_id")
      .eq("id", charge.id)
      .maybeSingle();
    venueId = typeof data?.venue_id === "string" ? data.venue_id : "";
  }
  const { data: venue } = await admin
    .from("venues")
    .select("pagbank_account_id")
    .eq("id", venueId)
    .maybeSingle();
  const venueAccount = typeof venue?.pagbank_account_id === "string"
    ? venue.pagbank_account_id.trim()
    : "";
  let primary = "";
  try {
    primary = pagbank.accountId().trim();
  } catch (_error) {
    primary = "";
  }
  return [venueAccount, primary].filter((item, index, all) =>
    item.length > 0 && all.indexOf(item) === index
  );
}

function nextCustodyAttempt(current: number | null | undefined): number {
  const value = Number(current ?? 0);
  if (!Number.isInteger(value) || value < 0) return 1;
  return value + 1;
}

/// Cobrança paga, com split, ainda sem custódia solta. O cron chama isto.
export async function retryPendingCustodyReleases(
  admin: Admin,
  pagbank: CustodyClient,
): Promise<number> {
  if (typeof admin?.from !== "function") return 0;
  const { data, error } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, provider_split_id, status, custody_released_at, custody_release_attempts, created_at, groups!inner(confirmed_at, closed_at, cancelled_at)",
    )
    .eq("status", "paid")
    .is("custody_released_at", null)
    .not("provider_split_id", "is", null)
    .or(
      `custody_release_attempts.is.null,custody_release_attempts.lt.${maxCustodyReleaseAttempts}`,
    )
    .or("confirmed_at.not.is.null,closed_at.not.is.null", {
      referencedTable: "groups",
    })
    .order("created_at", { ascending: true })
    .limit(40);
  if (error || !Array.isArray(data)) return 0;
  let released = 0;
  for (const row of data) {
    const charge = row as CustodyCharge & { group_id?: string };
    if (!charge.group_id) continue;
    if ((charge.custody_release_attempts ?? 0) >= maxCustodyReleaseAttempts) {
      continue;
    }
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
