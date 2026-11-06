import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { maySettle, settleGroup } from "../_shared/settle_group.ts";

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
      const allowed = await maySettle(
        admin,
        groupId,
        userData.user.id,
        Boolean(adminRow),
      );
      if (!allowed) continue;
      await settleGroup(admin, asaas, groupId);
      settled.push(groupId);
    }
    return json({ settled });
  } catch (error) {
    const failure = clientFailure(error, "settle-charges");
    return json(failure.body, failure.status);
  }
});
