// Aplica o status que o webhook ou a consulta periódica viram no PagBank.

import { logCaught } from "./pagbank_client_error.ts";
import { PagBankProvider } from "./pagbank_provider.ts";
import { releasePaidIfClosed } from "./custody_release.ts";
import { bandConfirmed } from "./group_band.ts";
import {
  cancelInvoicesForCharge,
  issuePaidInvoices,
} from "./issue_invoices.ts";
import {
  confirmedChargeStatus,
  movesMoney,
  paymentRefForRead,
  requestedChargeStatus,
} from "./charge_patch.ts";
import { applyPaymentTransition } from "./ledger.ts";
import { syncPayerDocument } from "./payer_document.ts";
import { settlePaidChargeReserve } from "./points_reserve.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

type EnvLike = { get(name: string): string | undefined };

export type NoticeCharge = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
  status: string;
  billing_type: string;
  provider_ref: string | null;
  provider_split_id?: string | null;
  custody_released_at?: string | null;
};

/// null = o status não move a cobrança.
export async function applyPagBankNotice(input: {
  admin: Admin;
  env: EnvLike;
  pagbank: PagBankProvider;
  charge: NoticeCharge;
  paymentStatus: string;
}): Promise<string | null> {
  const requested = requestedChargeStatus("", input.paymentStatus);
  if (!requested) return null;

  let next = requested;
  const confirmRemote = movesMoney(requested) || requested === "cancelled" ||
    requested === "failed";
  if (confirmRemote) {
    const providerRef = paymentRefForRead(input.charge.provider_ref, "");
    if (!providerRef) throw new Error("ledger_write_failed");
    const remote = await input.pagbank.getPayment(providerRef);
    const confirmed = confirmedChargeStatus(remote.status);
    if (!confirmed) throw new Error("ledger_write_failed");
    next = confirmed;
  }

  const credit = next === "paid" &&
    await groupIsClosed(input.admin, input.charge.group_id);
  if (next === "paid") {
    await syncPayerDocument(input.admin, input.pagbank, {
      id: input.charge.id,
      user_id: input.charge.user_id,
      billing_type: input.charge.billing_type,
      provider_ref: input.charge.provider_ref,
    });
  }
  const result = await applyPaymentTransition(
    input.admin,
    input.charge.id,
    next,
    credit,
  );
  const status = result.status;
  const sandbox = input.pagbank.sandbox;
  const pagbank = sandbox ? undefined : input.pagbank;
  if (status === "paid") {
    const live = pagbank ?? input.pagbank;
    await releasePaidIfClosed({
      admin: input.admin,
      pagbank: live,
      charge: input.charge,
      groupClosed: credit,
    }).catch((error) => {
      logCaught("custody_release_failed", error);
    });
    await settlePaidChargeReserve(input.admin, input.env, input.charge.id)
      .catch((error) => {
        logCaught("pagbank-webhook", error);
      });
    await issuePaidInvoices(input.admin, input.charge, { sandbox, pagbank })
      .catch((error) => {
        logCaught("pagbank-webhook", error);
      });
  }
  if (status === "refunded") {
    await cancelInvoicesForCharge(input.admin, input.charge.id, {
      sandbox,
      pagbank,
    }).catch((error) => {
      logCaught("pagbank-webhook", error);
    });
  }
  return status;
}

/// Pix e pedidos ainda pendentes. O webhook é o caminho normal.
/// Isto cobre o aviso que não chegou.
export async function pollPendingPagBankCharges(
  admin: Admin,
  pagbank: PagBankProvider,
  env: EnvLike,
): Promise<number> {
  if (typeof admin?.from !== "function") return 0;
  const { data, error } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, billing_type, provider_ref, provider_split_id, custody_released_at, created_at",
    )
    .eq("status", "pending")
    .not("provider_ref", "is", null)
    .order("created_at", { ascending: true })
    .limit(20);
  if (error || !Array.isArray(data)) return 0;
  let applied = 0;
  for (const row of data) {
    const charge = row as NoticeCharge;
    const ref = (charge.provider_ref ?? "").trim();
    if (!ref) continue;
    try {
      const remote = await pagbank.getPayment(ref);
      const before = charge.status;
      const status = await applyPagBankNotice({
        admin,
        env,
        pagbank,
        charge,
        paymentStatus: remote.status,
      });
      if (status && status !== before) applied += 1;
    } catch (error) {
      logCaught("pending_charge_poll", error);
    }
  }
  return applied;
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
