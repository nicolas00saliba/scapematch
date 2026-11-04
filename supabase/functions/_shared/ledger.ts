import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { commissionCents } from "./asaas_provider.ts";

export type ChargeRow = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
};

type Admin = ReturnType<typeof createClient>;

async function hasLine(
  admin: Admin,
  chargeId: string,
  kind: string,
  direction: string,
): Promise<boolean> {
  const { data } = await admin
    .from("ledger_entries")
    .select("id")
    .eq("payment_charge_id", chargeId)
    .eq("kind", kind)
    .eq("direction", direction)
    .maybeSingle();
  return Boolean(data);
}

export async function creditLedger(admin: Admin, charge: ChargeRow) {
  const fee = commissionCents(charge.amount_cents, charge.commission_bps);
  const net = charge.amount_cents - fee;
  if (net > 0 && !(await hasLine(admin, charge.id, "house_net", "credit"))) {
    await admin.from("ledger_entries").insert({
      venue_id: charge.venue_id,
      group_id: charge.group_id,
      user_id: charge.user_id,
      account: "house",
      direction: "credit",
      kind: "house_net",
      amount_cents: net,
      payment_charge_id: charge.id,
    });
  }
  if (fee > 0 && !(await hasLine(admin, charge.id, "commission", "credit"))) {
    await admin.from("ledger_entries").insert({
      venue_id: charge.venue_id,
      group_id: charge.group_id,
      user_id: charge.user_id,
      account: "platform",
      direction: "credit",
      kind: "commission",
      amount_cents: fee,
      payment_charge_id: charge.id,
    });
  }
}

export async function reverseLedger(admin: Admin, charge: ChargeRow) {
  const { data: credits } = await admin
    .from("ledger_entries")
    .select("account, kind, amount_cents")
    .eq("payment_charge_id", charge.id)
    .eq("direction", "credit");
  for (const line of credits ?? []) {
    const kind = line.kind === "commission" ? "commission_refund" : "house_refund";
    if (await hasLine(admin, charge.id, kind, "debit")) continue;
    await admin.from("ledger_entries").insert({
      venue_id: charge.venue_id,
      group_id: charge.group_id,
      user_id: charge.user_id,
      account: line.account,
      direction: "debit",
      kind,
      amount_cents: line.amount_cents,
      payment_charge_id: charge.id,
    });
  }
}
