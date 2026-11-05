import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "./asaas_provider.ts";
import { cancelInvoicesForCharge } from "./issue_invoices.ts";
import {
  applyPaymentTransition,
  type ChargeRow,
  reverseLedger,
} from "./ledger.ts";

type Admin = ReturnType<typeof createClient>;

type Charge = ChargeRow & {
  status: string;
  provider_ref: string | null;
  billing_type: string;
};

/// Estorna Pix pago e cancela autorização de cartão. `refunded` só entra
/// depois que a API do Asaas responde com sucesso.
export async function releaseCancelledCharges(
  admin: Admin,
  asaas: AsaasProvider,
  groupId: string,
): Promise<string[]> {
  const { data: charges } = await admin
    .from("payment_charges")
    .select(
      "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, provider_ref, billing_type",
    )
    .eq("group_id", groupId);

  const stillPending: string[] = [];
  for (const charge of charges ?? []) {
    const row = charge as Charge;
    if (!row.provider_ref) continue;
    if (
      row.status === "refunded" || row.status === "cancelled" ||
      row.status === "failed"
    ) {
      continue;
    }
    try {
      if (row.status === "paid") {
        await asaas.refund(row.provider_ref);
        await reverseLedger(admin, row);
        await markMember(admin, groupId, row.user_id, "refunded");
        await cancelInvoicesForCharge(admin, row.id, {
          sandbox: asaas.sandbox,
          asaas,
        });
        continue;
      }
      await asaas.cancelAuthorization(row.provider_ref);
      const cancelled = await applyPaymentTransition(
        admin,
        row.id,
        "cancelled",
        false,
      );
      if (cancelled.status !== "cancelled") {
        stillPending.push(row.id);
        continue;
      }
      await markMember(admin, groupId, row.user_id, "none");
    } catch (_error) {
      stillPending.push(row.id);
    }
  }
  return stillPending;
}

async function markMember(
  admin: Admin,
  groupId: string,
  userId: string,
  refundStatus: "refunded" | "none",
) {
  const { data: member } = await admin
    .from("group_members")
    .select("refund_reason")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .maybeSingle();
  const current = member?.refund_reason as string | undefined;
  const reason = current && current !== "none"
    ? current
    : refundStatus === "refunded"
    ? "group_did_not_close"
    : "hold_released";
  await admin.from("group_members").update({
    payment_status: "released",
    refund_status: refundStatus,
    refund_reason: reason,
  }).eq("group_id", groupId).eq("user_id", userId);
}
