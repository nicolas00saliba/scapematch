import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import {
  PagBankProvider,
  isPagBankSandbox,
  pagbankSignatureMatches,
} from "../_shared/pagbank_provider.ts";
import { bandConfirmed } from "../_shared/group_band.ts";
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
  splitDivergenceEvent,
} from "../_shared/charge_patch.ts";
import { applyPaymentTransition } from "../_shared/ledger.ts";
import { syncPayerDocument } from "../_shared/payer_document.ts";
import { settlePaidChargeReserve } from "../_shared/points_reserve.ts";

Deno.serve(async (req) => {
  // Servidor a servidor: a resposta segue mesmo sem o header de navegador.
  const json = bindJson(req);
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const raw = await req.text();
  const expected = Deno.env.get("PAGBANK_WEBHOOK_SECRET") ||
    Deno.env.get("PAGBANK_TOKEN");
  const header = req.headers.get("x-authenticity-token");
  if (!await pagbankSignatureMatches(header, expected, raw)) {
    return json({ error: "unauthorized" }, 401);
  }

  let paymentId = "";
  try {
    const payload = JSON.parse(raw) as {
      id?: string;
      status?: string;
      event?: string;
      charges?: { id?: string; status?: string }[];
      payment?: { id?: string; status?: string; billingType?: string };
    };
    const charge = payload.charges?.find((item) => item?.id);
    paymentId = charge?.id ?? payload.payment?.id ?? payload.id ?? "";
    const paymentStatus = charge?.status ?? payload.payment?.status ??
      payload.status ?? "";
    if (!paymentId) return json({ ok: true });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const divergence = splitDivergenceEvent(payload?.event ?? "");
    if (divergence) {
      console.error(`split_divergence ${divergence} ${paymentId}`);
      await admin.rpc("note_split_divergence", {
        p_provider_ref: paymentId,
        p_event: divergence,
      });
    }

    const { data: charge } = await admin
      .from("payment_charges")
      .select(
        "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, billing_type, provider_ref",
      )
      .eq("provider_ref", paymentId)
      .maybeSingle();
    if (!charge) return json({ ok: true });

    const requested = requestedChargeStatus(
      payload.event ?? "",
      paymentStatus,
    );
    if (!requested) return json({ ok: true });

    let next = requested;
    if (movesMoney(requested)) {
      const providerRef = paymentRefForRead(charge.provider_ref, paymentId);
      if (!providerRef) throw new Error("ledger_write_failed");
      const pagbank = PagBankProvider.fromEnv(Deno.env);
      const remote = await pagbank.getPayment(providerRef);
      const confirmed = confirmedChargeStatus(remote.status);
      if (!confirmed) throw new Error("ledger_write_failed");
      next = confirmed;
    }

    const credit = next === "paid" &&
      await groupIsClosed(admin, charge.group_id);
    if (next === "paid") {
      await syncPayerDocument(admin, safePagBank(), {
        id: charge.id,
        user_id: charge.user_id,
        billing_type: charge.billing_type,
        provider_ref: charge.provider_ref,
      });
    }
    const result = await applyPaymentTransition(admin, charge.id, next, credit);
    const status = result.status;

    const sandbox = isPagBankSandbox(
      Deno.env.get("PAGBANK_BASE_URL") ?? "https://sandbox.api.pagseguro.com",
    );
    const pagbank = sandbox ? undefined : safePagBank();
    if (status === "paid") {
      await settlePaidChargeReserve(admin, Deno.env, charge.id).catch(
        (error) => {
          logCaught("pagbank-webhook", error);
        },
      );
      await issuePaidInvoices(admin, charge, { sandbox, pagbank }).catch(
        (error) => {
          logCaught("pagbank-webhook", error);
        },
      );
    }
    if (status === "refunded") {
      await cancelInvoicesForCharge(admin, charge.id, { sandbox, pagbank }).catch(
        (error) => {
          logCaught("pagbank-webhook", error);
        },
      );
    }
    return json({ ok: true });
  } catch (error) {
    const failure = clientFailure(error, "pagbank-webhook");
    await noteWebhookError(failure.body.error, paymentId);
    return json(failure.body, failure.status);
  }
});

async function noteWebhookError(
  code: string,
  providerRef: string,
): Promise<void> {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const { error } = await admin.rpc("note_webhook_error", {
      p_source: "pagbank-webhook",
      p_code: code,
      p_provider_ref: providerRef,
    });
    if (error) logCaught("pagbank-webhook", new Error("note_webhook_error"));
  } catch (error) {
    logCaught("pagbank-webhook", error);
  }
}

function safePagBank(): PagBankProvider | undefined {
  try {
    return PagBankProvider.fromEnv(Deno.env);
  } catch (error) {
    logCaught("pagbank-webhook", error);
    return undefined;
  }
}

async function groupIsClosed(
  admin: ReturnType<typeof createClient>,
  groupId: string,
): Promise<boolean> {
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
