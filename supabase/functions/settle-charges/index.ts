import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { issuePaidInvoices } from "../_shared/issue_invoices.ts";
import { creditLedger, type ChargeRow } from "../_shared/ledger.ts";
import { releaseCancelledCharges } from "../_shared/release_charges.ts";

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData } = await userClient.auth.getUser();
    if (!userData.user) return json({ error: "not authenticated" }, 401);

    const admin = createClient(url, service);
    const body = await req.json().catch(() => ({})) as {
      group_id?: string;
      sweep?: boolean;
    };
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();

    const ids: string[] = [];
    if (body.sweep) {
      if (!adminRow) return json({ error: "not admin" }, 403);
      const { data: groups } = await admin
        .from("groups")
        .select("id")
        .or("cancelled_at.not.is.null,closed_at.not.is.null");
      for (const group of groups ?? []) ids.push(group.id as string);
    } else if (body.group_id) {
      ids.push(body.group_id);
    } else {
      return json({ error: "group_id obrigatório" }, 400);
    }

    const asaas = AsaasProvider.fromEnv(Deno.env);
    const settled: string[] = [];
    for (const groupId of ids) {
      const allowed = await canSettle(admin, groupId, userData.user.id, Boolean(adminRow));
      if (!allowed) continue;
      await settleOne(admin, asaas, groupId);
      settled.push(groupId);
    }
    return json({ settled });
  } catch (error) {
    const failure = clientFailure(error, "settle-charges");
    return json(failure.body, failure.status);
  }
});

async function canSettle(
  admin: ReturnType<typeof createClient>,
  groupId: string,
  userId: string,
  isAdmin: boolean,
): Promise<boolean> {
  if (isAdmin) return true;
  const { data: group } = await admin
    .from("groups")
    .select("created_by, venue_id")
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return false;
  if (group.created_by === userId) return true;
  const { data: venue } = await admin
    .from("venues")
    .select("owner_id")
    .eq("id", group.venue_id)
    .maybeSingle();
  return venue?.owner_id === userId;
}

async function settleOne(
  admin: ReturnType<typeof createClient>,
  asaas: AsaasProvider,
  groupId: string,
) {
  const { data: group } = await admin
    .from("groups")
    .select("id, cancelled_at, closed_at, closes_at, starts_at, total_spots, minimum_spots")
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  const filled = count ?? 0;
  const closed = Boolean(group.closed_at) ||
    (filled >= group.total_spots && filled >= group.minimum_spots);
  const missed = !group.cancelled_at && !closed && group.closes_at &&
    new Date(group.closes_at).getTime() <= Date.now() &&
    filled < group.minimum_spots;
  const release = Boolean(group.cancelled_at) || missed;

  if (release) {
    await releaseCancelledCharges(admin, asaas, groupId);
    return;
  }

  // commission_bps é a taxa fotografada na cobrança por create-charge.
  const { data: charges } = await admin
    .from("payment_charges")
    .select("id, group_id, user_id, venue_id, amount_cents, commission_bps, status, provider_ref, billing_type")
    .eq("group_id", groupId);

  for (const charge of charges ?? []) {
    const row = charge as ChargeRow & {
      status: string;
      provider_ref: string | null;
      billing_type: string;
    };
    if (!row.provider_ref) continue;
    if (closed && row.status === "authorized" && row.billing_type === "CREDIT_CARD") {
      const captured = await asaas.capture(row.provider_ref);
      const paid = captured.status === "CONFIRMED" || captured.status === "RECEIVED";
      await admin.from("payment_charges").update({
        status: paid ? "paid" : "authorized",
        paid_at: paid ? new Date().toISOString() : null,
      }).eq("id", row.id);
      if (paid) {
        await admin.from("group_members").update({ payment_status: "paid" })
          .eq("group_id", groupId)
          .eq("user_id", row.user_id);
        await creditLedger(admin, row);
        await issuePaidInvoices(admin, row, {
          sandbox: asaas.sandbox,
          asaas: asaas.sandbox ? undefined : asaas,
        });
      }
      continue;
    }
    if (closed && row.status === "paid") {
      await creditLedger(admin, row);
      await issuePaidInvoices(admin, row, {
        sandbox: asaas.sandbox,
        asaas: asaas.sandbox ? undefined : asaas,
      });
    }
  }
}
