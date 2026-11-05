import { commissionCents } from "./asaas_provider.ts";
import { insertLedgerLine, type LedgerLine } from "./ledger_write.ts";

export type ChargeRow = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
};

type Admin = {
  from(table: string): any;
};

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
    .limit(1)
    .maybeSingle();
  return Boolean(data);
}

function ledgerLine(
  charge: ChargeRow,
  line: Pick<LedgerLine, "account" | "direction" | "kind" | "amount_cents">,
): LedgerLine {
  return {
    venue_id: charge.venue_id,
    group_id: charge.group_id,
    user_id: charge.user_id,
    payment_charge_id: charge.id,
    ...line,
  };
}

export async function creditLedger(admin: Admin, charge: ChargeRow) {
  const fee = commissionCents(charge.amount_cents, charge.commission_bps);
  const net = charge.amount_cents - fee;
  if (net > 0 && !(await hasLine(admin, charge.id, "house_net", "credit"))) {
    await insertLedgerLine(
      admin.from("ledger_entries"),
      ledgerLine(charge, {
        account: "house",
        direction: "credit",
        kind: "house_net",
        amount_cents: net,
      }),
    );
  }
  if (fee > 0 && !(await hasLine(admin, charge.id, "commission", "credit"))) {
    await insertLedgerLine(
      admin.from("ledger_entries"),
      ledgerLine(charge, {
        account: "platform",
        direction: "credit",
        kind: "commission",
        amount_cents: fee,
      }),
    );
  }
}

export async function reverseLedger(admin: Admin, charge: ChargeRow) {
  const { data: credits } = await admin
    .from("ledger_entries")
    .select("account, kind, amount_cents")
    .eq("payment_charge_id", charge.id)
    .eq("direction", "credit");
  for (const line of credits ?? []) {
    const kind = line.kind === "commission"
      ? "commission_refund"
      : "house_refund";
    if (await hasLine(admin, charge.id, kind, "debit")) continue;
    await insertLedgerLine(
      admin.from("ledger_entries"),
      ledgerLine(charge, {
        account: line.account,
        direction: "debit",
        kind,
        amount_cents: line.amount_cents,
      }),
    );
  }
}
