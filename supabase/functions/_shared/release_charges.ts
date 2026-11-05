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
    } catch (_error) {
      stillPending.push(row.id);
    }
  }
  return stillPending;
}
