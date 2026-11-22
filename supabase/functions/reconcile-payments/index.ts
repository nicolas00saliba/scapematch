import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { logCaught } from "../_shared/client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";
import {
  expireUnconfirmedGroups,
  settleAuthorizedCards,
  settleGroup,
} from "../_shared/settle_group.ts";
import { secretMatches } from "../_shared/venue_payouts.ts";

type Deps = {
  // deno-lint-ignore no-explicit-any
  admin?: any;
  reconcileSecret?: string;
};

export async function handleReconcile(
  req: Request,
  deps?: Deps,
): Promise<Response> {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  const secret = deps?.reconcileSecret ?? Deno.env.get("RECONCILE_SECRET") ??
    "";
  const header = req.headers.get("x-reconcile-secret") ?? "";
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  try {
    const admin = deps?.admin ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const groupId = await settleGroupId(req);
    const reconciled = await reconcilePayments(admin);
    const expired = await expireUnconfirmedGroups(admin);
    for (const id of expired) {
      try {
        await settleGroup(admin, id);
      } catch (error) {
        logCaught("settle-charges", error);
      }
    }
    if (groupId) {
      try {
        await settleGroup(admin, groupId);
      } catch (error) {
        logCaught("settle-charges", error);
      }
    }
    await settleAuthorizedCards(admin);
    const released = await admin.rpc("release_due_scape_points");
    if (released.error) throw new Error("points");
    return json(reconciled);
  } catch (error) {
    logCaught("reconcile-payments", error);
    return json({ error: "erro" }, 500);
  }
}

const groupIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function settleGroupId(req: Request): Promise<string> {
  try {
    const body = await req.clone().json();
    const raw = body && typeof body === "object"
      ? (body as { settle_group_id?: unknown; group_id?: unknown })
      : null;
    const id = raw?.settle_group_id ?? raw?.group_id ?? "";
    return typeof id === "string" && groupIdPattern.test(id.trim())
      ? id.trim()
      : "";
  } catch {
    return "";
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleReconcile(req));
}
