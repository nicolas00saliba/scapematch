import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/pagbank_client_error.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { retryPendingCustodyReleases } from "../_shared/custody_release.ts";
import { pollPendingPagBankCharges } from "../_shared/charge_notice.ts";
import {
  expireUnconfirmedGroups,
  maySettle,
  settleGroup,
} from "../_shared/settle_group.ts";
import { adminWithMfa } from "../_shared/admin_session.ts";
import {
  memberRefundActor,
  processMemberRefunds,
} from "../_shared/member_refund.ts";

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
    const { data: adminLookup } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    const adminRow = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as {
      group_id?: string;
      sweep?: boolean;
      member_refund?: boolean;
    };
    if (body.member_refund) {
      const groupId = body.group_id ?? "";
      if (!groupId) return json({ error: "group_id obrigatório" }, 400);
      const scope = await memberRefundActor(
        admin,
        groupId,
        userData.user.id,
        Boolean(adminRow),
      );
      if (!scope) return json({ error: "not member" }, 403);
      const pagbank = PagBankProvider.fromEnv(Deno.env);
      const refunds = await processMemberRefunds(admin, pagbank, {
        groupId,
        userId: scope.userId,
      });
      return json({ refunds });
    }

    const ids: string[] = [];
    if (body.sweep) {
      if (!adminRow) return json({ error: "not admin" }, 403);
      const { data: groups } = await admin
        .from("groups")
        .select("id")
        .or(
          "cancelled_at.not.is.null,confirmed_at.not.is.null,closed_at.not.is.null",
        );
      for (const group of groups ?? []) ids.push(group.id as string);
      for (const id of await expireUnconfirmedGroups(admin)) {
        if (!ids.includes(id)) ids.push(id);
      }
    } else if (body.group_id) {
      ids.push(body.group_id);
    } else {
      return json({ error: "group_id obrigatório" }, 400);
    }

    const pagbank = PagBankProvider.fromEnv(Deno.env);
    const settled: string[] = [];
    for (const groupId of ids) {
      const allowed = await maySettle(
        admin,
        groupId,
        userData.user.id,
        Boolean(adminRow),
      );
      if (!allowed) continue;
      await settleGroup(admin, pagbank, groupId);
      settled.push(groupId);
    }
    await processMemberRefunds(admin, pagbank);
    await pollPendingPagBankCharges(admin, pagbank, Deno.env);
    await retryPendingCustodyReleases(admin, pagbank);
    return json({ settled });
  } catch (error) {
    const failure = clientFailure(error, "settle-charges");
    return json(failure.body, failure.status);
  }
});
