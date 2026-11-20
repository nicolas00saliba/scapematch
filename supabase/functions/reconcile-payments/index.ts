import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { logCaught } from "../_shared/client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";
import { settleAuthorizedCards, settleGroup } from "../_shared/settle_group.ts";

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    const header = req.headers.get("x-reconcile-secret") ?? "";
    const expected = Deno.env.get("RECONCILE_SECRET") ?? "";
    if (!expected || header !== expected) {
      return json({ error: "not authenticated" }, 401);
    }
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const admin = createClient(url, service);
    const reconciled = await reconcilePayments(admin);
    const body = await req.json().catch(() => ({})) as { group_id?: string };
    if (body.group_id) await settleGroup(admin, body.group_id);
    else await settleAuthorizedCards(admin);
    return json(reconciled);
  } catch (error) {
    logCaught("reconcile-payments", error);
    return json({ error: "erro" }, 500);
  }
});
