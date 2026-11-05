import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientDbError, clientFailure } from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
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

    const body = await req.json().catch(() => ({})) as {
      group_id?: string;
      reason?: string;
      action?: string;
    };
    const groupId = body.group_id ?? "";
    if (!groupId) return json({ error: "group_id obrigatório" }, 400);

    const admin = createClient(url, service);
    if (body.action === "release") {
      const allowed = await canRelease(admin, groupId, userData.user.id);
      if (!allowed) return json({ error: "not owner" }, 403);
      const { data: group } = await admin
        .from("groups")
        .select("cancelled_at")
        .eq("id", groupId)
        .maybeSingle();
      if (!group?.cancelled_at) {
        return json({ error: "group not cancelled" }, 409);
      }
    } else {
      const { error } = await userClient.rpc("house_cancel_group", {
        p_group_id: groupId,
        p_reason: body.reason ?? "Cancelada pela casa",
      });
      if (error) {
        return json({
          error: clientDbError(error, "cancel-house-group"),
        }, 400);
      }
    }

    const asaas = AsaasProvider.fromEnv(Deno.env);
    const pending = await releaseCancelledCharges(admin, asaas, groupId);
    return json({ cancelled: true, pending });
  } catch (error) {
    const failure = clientFailure(error, "cancel-house-group");
    return json(failure.body, failure.status);
  }
});

async function canRelease(
  admin: ReturnType<typeof createClient>,
  groupId: string,
  userId: string,
): Promise<boolean> {
  const { data: adminRow } = await admin
    .from("admins")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (adminRow) return true;
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
