import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import {
  AsaasProvider,
  isAsaasSandbox,
  tokensMatch,
} from "../_shared/asaas_provider.ts";
import { json } from "../_shared/http.ts";
import {
  cancelInvoicesForCharge,
  issuePaidInvoices,
} from "../_shared/issue_invoices.ts";
import { creditLedger, reverseLedger } from "../_shared/ledger.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const expected = Deno.env.get("ASAAS_WEBHOOK_TOKEN");
  const header = req.headers.get("asaas-access-token");
  if (!tokensMatch(header, expected)) return json({ error: "unauthorized" }, 401);

  const payload = await req.json().catch(() => null) as {
    event?: string;
    payment?: { id?: string; status?: string; billingType?: string };
  } | null;
  const paymentId = payload?.payment?.id;
  if (!paymentId) return json({ ok: true });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data: charge } = await admin
    .from("payment_charges")
    .select("id, group_id, user_id, venue_id, amount_cents, commission_bps, status, billing_type")
    .eq("provider_ref", paymentId)
    .maybeSingle();
  if (!charge) return json({ ok: true });

  const event = payload?.event ?? "";
  const remoteStatus = payload?.payment?.status ?? "";
  let status = charge.status as string;
  if (event === "PAYMENT_REFUNDED" || remoteStatus === "REFUNDED") {
    status = "refunded";
  } else if (
    event === "PAYMENT_RECEIVED" || event === "PAYMENT_CONFIRMED" ||
    remoteStatus === "RECEIVED" || remoteStatus === "CONFIRMED"
  ) {
    status = "paid";
  } else if (remoteStatus === "AUTHORIZED" || event === "PAYMENT_AUTHORIZED") {
    status = "authorized";
  }

  await admin.from("payment_charges").update({
    status,
    paid_at: status === "paid" ? new Date().toISOString() : charge.status === "paid" ? undefined : null,
    refunded_at: status === "refunded" ? new Date().toISOString() : null,
  }).eq("id", charge.id);

  const memberPayment = status === "paid"
    ? "paid"
    : status === "authorized"
    ? "reserved"
    : status === "refunded"
    ? "released"
    : "pending";
  await admin.from("group_members").update({
    payment_status: memberPayment,
    refund_status: status === "refunded" ? "refunded" : "none",
    refund_reason: status === "refunded" ? "group_did_not_close" : "none",
  }).eq("group_id", charge.group_id).eq("user_id", charge.user_id);

  const sandbox = isAsaasSandbox(
    Deno.env.get("ASAAS_BASE_URL") ?? "https://api-sandbox.asaas.com/v3",
  );
  const asaas = sandbox ? undefined : safeAsaas();
  if (status === "paid") {
    await creditIfGroupClosed(admin, charge);
    await issuePaidInvoices(admin, charge, { sandbox, asaas }).catch(
      (error) => {
        console.error(error);
      },
    );
  }
  if (status === "refunded") {
    await reverseLedger(admin, charge);
    await cancelInvoicesForCharge(admin, charge.id, { sandbox, asaas }).catch(
      (error) => {
        console.error(error);
      },
    );
  }
  return json({ ok: true });
});

function safeAsaas(): AsaasProvider | undefined {
  try {
    return AsaasProvider.fromEnv(Deno.env);
  } catch (error) {
    console.error(error);
    return undefined;
  }
}

async function creditIfGroupClosed(
  admin: ReturnType<typeof createClient>,
  charge: {
    id: string;
    group_id: string;
    user_id: string;
    venue_id: string;
    amount_cents: number;
    commission_bps: number;
  },
) {
  const { data: group } = await admin
    .from("groups")
    .select("closed_at, total_spots, minimum_spots, cancelled_at")
    .eq("id", charge.group_id)
    .maybeSingle();
  if (!group || group.cancelled_at) return;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", charge.group_id)
    .neq("attendance", "cancelled");
  const filled = count ?? 0;
  const closed = Boolean(group.closed_at) || filled >= group.total_spots;
  if (!closed || filled < group.minimum_spots) return;
  await creditLedger(admin, charge);
}
