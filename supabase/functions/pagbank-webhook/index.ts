import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import {
  PagBankProvider,
  pagbankSignatureMatches,
} from "../_shared/pagbank_provider.ts";
import {
  applyPagBankNotice,
  pagbankNoticeRefs,
  type NoticeCharge,
} from "../_shared/charge_notice.ts";
import { bindJson } from "../_shared/http.ts";

Deno.serve(async (req) => {
  // Servidor a servidor: a resposta segue mesmo sem o header de navegador.
  const json = bindJson(req);
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const raw = await req.text();
  const override = (Deno.env.get("PAGBANK_WEBHOOK_SECRET") ?? "").trim();
  const expected = override || (Deno.env.get("PAGBANK_TOKEN") ?? "").trim();
  const header = req.headers.get("x-authenticity-token");
  if (!await pagbankSignatureMatches(header, expected, raw)) {
    return json({ error: "unauthorized" }, 401);
  }

  let paymentId = "";
  try {
    const payload = JSON.parse(raw) as {
      id?: string;
      status?: string;
      charges?: { id?: string; status?: string }[];
    };
    const refs = pagbankNoticeRefs(payload);
    if (refs.length === 0) return json({ ok: true });
    const notice = payload.charges?.find((item) => item?.id);
    const paymentStatus = notice?.status ?? payload.status ?? "";

    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    let charge: NoticeCharge | null = null;
    for (const ref of refs) {
      const { data } = await admin
        .from("payment_charges")
        .select(
          "id, group_id, user_id, venue_id, amount_cents, commission_bps, status, billing_type, provider_ref, provider_split_id, custody_released_at",
        )
        .eq("provider_ref", ref)
        .maybeSingle();
      if (data) {
        charge = data as NoticeCharge;
        paymentId = ref;
        break;
      }
    }
    if (!charge) return json({ ok: true });

    const pagbank = PagBankProvider.fromEnv(Deno.env);
    await applyPagBankNotice({
      admin,
      env: Deno.env,
      pagbank,
      charge,
      paymentStatus,
    });
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
