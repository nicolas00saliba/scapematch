// Solta a custódia HELD quando a sessão já começou.
// Confirmação e captura continuam antes. Falha fica na cobrança e o cron tenta de novo.
// A mesma regra está em public.custody_release_due.

import { logCaught } from "./pagbank_client_error.ts";
import {
  bandConfirmed,
  joinedAtFromRows,
  minimumReachedOnTime,
} from "./group_band.ts";
import { captureOpsAlert } from "./sentry_ops.ts";
import {
  bindingAlertCode,
  bindingBlocksMoney,
  parseBinding,
} from "./pagbank_binding.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type CustodyClient = {
  releaseCustody(splitId: string, accountIds: string[]): Promise<void>;
  accountId(): string;
};

export type CustodyCharge = {
  id: string;
  group_id?: string | null;
  venue_id?: string | null;
  status?: string | null;
  provider_split_id?: string | null;
  custody_released_at?: string | null;
  refund_requested_at?: string | null;
  custody_release_attempts?: number | null;
  created_at?: string | null;
};

export type SessionClock = {
  startsAt: string | null;
  groupCancelledAt: string | null;
  sessionCancelledAt: string | null;
  refundRequestedAt: string | null;
  confirmed: boolean;
  stuckUnconfirmed: boolean;
  status: string | null;
};

/// Depois disto o cron para e o log custody_release_exhausted alerta.
export const maxCustodyReleaseAttempts = 8;

const blockedStatus = new Set(["refunded", "cancelled", "failed"]);

/// now >= início da sessão, grupo confirmado, sem cancelamento e sem estorno.
export function custodyReleaseDue(clock: SessionClock, now = Date.now()): boolean {
  if (clock.refundRequestedAt) return false;
  if (clock.groupCancelledAt) return false;
  if (clock.sessionCancelledAt) return false;
  if (clock.status && blockedStatus.has(clock.status)) return false;
  if (!clock.confirmed || clock.stuckUnconfirmed) return false;
  if (!clock.startsAt) return false;
  const start = Date.parse(clock.startsAt);
  if (!Number.isFinite(start)) return false;
  return now >= start;
}

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

/// Cartão capturado com o grupo já confirmado. A custódia espera a sessão.
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

/// Pix pago com o grupo já confirmado. Antes da sessão continua em custódia.
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
  if (charge.refund_requested_at) return false;
  if ((charge.custody_release_attempts ?? 0) >= maxCustodyReleaseAttempts) {
    return false;
  }
  const id = (charge.provider_split_id ?? "").trim();
  if (!id || !charge.id || charge.custody_released_at) return false;
  const now = Date.now();
  const clock = await loadSessionClock(admin, charge);
  if (clock.stuckUnconfirmed) {
    await alertUnconfirmedHeld();
    return false;
  }
  if (!custodyReleaseDue(clock, now)) return false;
  const sql = await sqlAllowsRelease(admin, charge.id, new Date(now).toISOString());
  if (sql === false) return false;
  // Conta da casa e token têm de ser da mesma conta. Se houver ambiguidade,
  // a custódia não solta e o alerta sai; o cron tenta de novo depois que
  // alguém decidir a conta. Não escolhe e não gasta tentativa.
  if (await bindingStopsRelease(admin, charge)) return false;
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

async function bindingStopsRelease(
  admin: Admin,
  charge: CustodyCharge,
): Promise<boolean> {
  if (typeof admin?.rpc !== "function") return false;
  let venueId = (charge.venue_id ?? "").trim();
  if (!venueId) {
    try {
      const { data } = await admin
        .from("payment_charges")
        .select("venue_id")
        .eq("id", charge.id)
        .maybeSingle();
      venueId = typeof data?.venue_id === "string" ? data.venue_id : "";
    } catch {
      venueId = "";
    }
  }
  if (!venueId) return false;
  let binding = parseBinding(null);
  try {
    const result = await admin.rpc("venue_pagbank_binding", {
      p_venue_id: venueId,
    });
    binding = result?.error ? parseBinding(null) : parseBinding(result?.data);
  } catch {
    binding = parseBinding(null);
  }
  if (!bindingBlocksMoney(binding)) return false;
  await captureOpsAlert({
    get(name: string) {
      try {
        return Deno.env.get(name);
      } catch {
        return undefined;
      }
    },
  }, fetch, { scope: "pagbank-custody", code: bindingAlertCode(binding) });
  return true;
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
    const row = recordOf(data);
    venueId = typeof row?.venue_id === "string" ? row.venue_id : "";
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

/// Cobrança paga, com split, sessão já iniciada, ainda sem custódia solta.
export async function retryPendingCustodyReleases(
  admin: Admin,
  pagbank: CustodyClient,
): Promise<number> {
  if (typeof admin?.from !== "function") return 0;
  const data = await dueCustodyCharges(admin);
  let released = 0;
  let stuck = false;
  for (const row of data) {
    const charge = row as CustodyCharge;
    if (!charge.group_id || charge.refund_requested_at) continue;
    if ((charge.custody_release_attempts ?? 0) >= maxCustodyReleaseAttempts) {
      continue;
    }
    if (!await groupIsClosed(admin, charge.group_id)) {
      if (await unprovenHeldGroup(admin, charge.group_id)) stuck = true;
      continue;
    }
    if (await releaseHeldSplit(admin, pagbank, charge)) released += 1;
  }
  if (stuck) await alertUnconfirmedHeld();
  return released;
}

async function dueCustodyCharges(admin: Admin): Promise<unknown[]> {
  if (typeof admin.rpc === "function") {
    try {
      const listed = await admin.rpc("list_due_custody_releases", {
        p_limit: 40,
      });
      if (!listed?.error && Array.isArray(listed.data)) return listed.data;
    } catch (_error) {
      // Sem a função, a consulta abaixo aplica o mesmo horário.
    }
  }
  const now = new Date().toISOString();
  const { data, error } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, venue_id, provider_split_id, status, custody_released_at, custody_release_attempts, refund_requested_at, created_at, groups!inner(confirmed_at, closed_at, cancelled_at, starts_at, session_id)",
    )
    .eq("status", "paid")
    .is("custody_released_at", null)
    .is("refund_requested_at", null)
    .not("provider_split_id", "is", null)
    .or(
      `custody_release_attempts.is.null,custody_release_attempts.lt.${maxCustodyReleaseAttempts}`,
    )
    .or("confirmed_at.not.is.null,closed_at.not.is.null", {
      referencedTable: "groups",
    })
    .or("cancelled_at.is.null", { referencedTable: "groups" })
    .or(`starts_at.lte."${now}"`, { referencedTable: "groups" })
    .order("created_at", { ascending: true })
    .limit(40);
  if (error || !Array.isArray(data)) return [];
  return data;
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
  if (bandConfirmed(group, count ?? 0)) return true;
  const joined = await memberJoinedAt(admin, groupId);
  return minimumReachedOnTime(
    textOrNull(group.closes_at),
    Number(group.minimum_spots ?? 0),
    joined ?? [],
  );
}

async function loadSessionClock(
  admin: Admin,
  charge: CustodyCharge,
): Promise<SessionClock> {
  let groupId = textOrNull(charge.group_id) ?? "";
  let refundAt = textOrNull(charge.refund_requested_at);
  let status = textOrNull(charge.status);
  if (charge.id && typeof admin?.from === "function") {
    const { data } = await admin
      .from("payment_charges")
      .select("group_id, refund_requested_at, status")
      .eq("id", charge.id)
      .maybeSingle();
    const fresh = recordOf(data);
    if (fresh) {
      if (!groupId) groupId = textOrNull(fresh.group_id) ?? "";
      refundAt = refundAt ?? textOrNull(fresh.refund_requested_at);
      const freshStatus = textOrNull(fresh.status);
      if (freshStatus) status = freshStatus;
    }
  }
  const empty: SessionClock = {
    startsAt: null,
    groupCancelledAt: null,
    sessionCancelledAt: null,
    refundRequestedAt: refundAt,
    confirmed: false,
    stuckUnconfirmed: false,
    status,
  };
  if (!groupId || typeof admin?.from !== "function") return empty;
  const { data: group } = await admin
    .from("groups")
    .select(
      "starts_at, cancelled_at, confirmed_at, closed_at, closes_at, total_spots, minimum_spots, session_id",
    )
    .eq("id", groupId)
    .maybeSingle();
  const groupRow = recordOf(group);
  if (!groupRow) return empty;
  let sessionStarts: string | null = null;
  let sessionCancelled: string | null = null;
  const sessionId = textOrNull(groupRow.session_id);
  if (sessionId) {
    const { data: session } = await admin
      .from("room_sessions")
      .select("starts_at, cancelled_at")
      .eq("id", sessionId)
      .maybeSingle();
    const sessionRow = recordOf(session);
    if (sessionRow) {
      sessionStarts = textOrNull(sessionRow.starts_at);
      sessionCancelled = textOrNull(sessionRow.cancelled_at);
    }
  }
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  const joined = await memberJoinedAt(admin, groupId);
  const closesAt = textOrNull(groupRow.closes_at);
  const minimum = Number(groupRow.minimum_spots ?? 0);
  const filled = joined ? joined.length : count ?? 0;
  const onTime = joined
    ? minimumReachedOnTime(closesAt, minimum, joined)
    : false;
  const confirmed = bandConfirmed({
    cancelled_at: textOrNull(groupRow.cancelled_at),
    confirmed_at: textOrNull(groupRow.confirmed_at),
    closed_at: textOrNull(groupRow.closed_at),
    closes_at: closesAt,
    total_spots: Number(groupRow.total_spots ?? 0),
    minimum_spots: minimum,
  }, filled) || onTime;
  const closes = closesAt ? Date.parse(closesAt) : NaN;
  const deadlinePassed = Number.isFinite(closes) && closes <= Date.now();
  return {
    startsAt: sessionStarts ?? textOrNull(groupRow.starts_at),
    groupCancelledAt: textOrNull(groupRow.cancelled_at),
    sessionCancelledAt: sessionCancelled,
    refundRequestedAt: refundAt,
    confirmed,
    stuckUnconfirmed: !confirmed &&
      !textOrNull(groupRow.cancelled_at) &&
      deadlinePassed &&
      filled >= minimum &&
      minimum > 0,
    status,
  };
}

async function memberJoinedAt(admin: Admin, groupId: string): Promise<string[] | null> {
  const { data, error } = await admin
    .from("group_members")
    .select("joined_at")
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  if (error) return null;
  return joinedAtFromRows(data);
}

async function unprovenHeldGroup(admin: Admin, groupId: string): Promise<boolean> {
  const clock = await loadSessionClock(admin, { id: "", group_id: groupId });
  return clock.stuckUnconfirmed;
}

async function alertUnconfirmedHeld(): Promise<void> {
  await captureOpsAlert({
    get(name: string) {
      try {
        return Deno.env.get(name);
      } catch {
        return undefined;
      }
    },
  }, fetch, {
    scope: "pagbank-custody",
    code: "unconfirmed_held",
  });
}

async function sqlAllowsRelease(
  admin: Admin,
  chargeId: string,
  nowIso: string,
): Promise<boolean | null> {
  if (typeof admin?.rpc !== "function") return null;
  try {
    const result = await admin.rpc("custody_release_due", {
      p_charge_id: chargeId,
      p_now: nowIso,
    });
    if (result?.error) return null;
    if (result?.data === true || result?.data === false) return result.data;
    return null;
  } catch (_error) {
    return null;
  }
}

function recordOf(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function textOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}
