import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/asaas_client_error.ts";
import {
  AsaasProvider,
  isAsaasSandbox,
  tokensMatch,
} from "../_shared/asaas_provider.ts";
import { bindJson } from "../_shared/http.ts";
import {
  cancelInvoicesForCharge,
  issuePaidInvoices,
} from "../_shared/issue_invoices.ts";
import {
  confirmedChargeStatus,
  movesMoney,
  paymentRefForRead,
  requestedChargeStatus,
} from "../_shared/charge_patch.ts";
import { applyPaymentTransition } from "../_shared/ledger.ts";
import { syncPayerDocument } from "../_shared/payer_document.ts";

Deno.serve(async (req) => {
  // Servidor a servidor: a resposta segue mesmo sem o header de navegador.
  const json = bindJson(req);
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const expected = Deno.env.get("ASAAS_WEBHOOK_TOKEN");
  const header = req.headers.get("asaas-access-token");
  if (!tokensMatch(header, expected)) {
    return json({ error: "unauthorized" }, 401);
  }

  try {
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
      .select(
        "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, billing_type, provider_ref",
      )
      .eq("provider_ref", paymentId)
      .maybeSingle();
    if (!charge) return json({ ok: true });

    const requested = requestedChargeStatus(
      payload?.event ?? "",
      payload?.payment?.status ?? "",
    );
    if (!requested) return json({ ok: true });

    let next = requested;
    if (movesMoney(requested)) {
      const providerRef = paymentRefForRead(charge.provider_ref, paymentId);
      if (!providerRef) throw new Error("ledger_write_failed");
      const asaas = AsaasProvider.fromEnv(Deno.env);
      const remote = await asaas.getPayment(providerRef);
      const confirmed = confirmedChargeStatus(remote.status);
      if (!confirmed) throw new Error("ledger_write_failed");
      next = confirmed;
    }

    const credit = next === "paid" &&
      await groupIsClosed(admin, charge.group_id);
    if (next === "paid") {
      await syncPayerDocument(admin, safeAsaas(), {
        id: charge.id,
        user_id: charge.user_id,
        billing_type: charge.billing_type,
        provider_ref: charge.provider_ref,
      });
    }
    const result = await applyPaymentTransition(admin, charge.id, next, credit);
    const status = result.status;

    const sandbox = isAsaasSandbox(
      Deno.env.get("ASAAS_BASE_URL") ?? "https://api-sandbox.asaas.com/v3",
    );
    const asaas = sandbox ? undefined : safeAsaas();
    if (status === "paid") {
      await issuePaidInvoices(admin, charge, { sandbox, asaas }).catch(
        (error) => {
          logCaught("asaas-webhook", error);
        },
      );
    }
    if (status === "refunded") {
      await cancelInvoicesForCharge(admin, charge.id, { sandbox, asaas }).catch(
        (error) => {
          logCaught("asaas-webhook", error);
        },
      );
    }
    return json({ ok: true });
  } catch (error) {
    const failure = clientFailure(error, "asaas-webhook");
    return json(failure.body, failure.status);
  }
});

function safeAsaas(): AsaasProvider | undefined {
  try {
    return AsaasProvider.fromEnv(Deno.env);
  } catch (error) {
    logCaught("asaas-webhook", error);
    return undefined;
  }
}

async function groupIsClosed(
  admin: ReturnType<typeof createClient>,
  groupId: string,
): Promise<boolean> {
  const { data: group } = await admin
    .from("groups")
    .select("closed_at, total_spots, minimum_spots, cancelled_at")
    .eq("id", groupId)
    .maybeSingle();
  if (!group || group.cancelled_at) return false;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  const filled = count ?? 0;
  const closed = Boolean(group.closed_at) || filled >= group.total_spots;
  return closed && filled >= group.minimum_spots;
}
