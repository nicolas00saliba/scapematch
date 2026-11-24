import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/pagbank_client_error.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { retryPendingCustodyReleases } from "../_shared/custody_release.ts";
import { pagbankCacClient, runPlatformCac } from "../_shared/platform_cac.ts";
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
import { reconcilePagBankTimeoutMs } from "../_shared/reconcile_payments.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

type SettleDeps = {
  user?: { id: string } | null;
  admin?: Admin;
  pagbank?: PagBankProvider;
};

export async function handleSettle(
  req: Request,
  deps?: SettleDeps,
): Promise<Response> {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const user = await settleUser(req, authHeader, deps);
    if (!user) return json({ error: "not authenticated" }, 401);

    const admin = deps?.admin ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const { data: adminLookup } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle();
    const adminRow = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as {
      group_id?: string;
      sweep?: boolean;
      member_refund?: boolean;
    };
    const pagbank = deps?.pagbank ??
      PagBankProvider.fromEnv(Deno.env, reconcilePagBankTimeoutMs);
    if (body.member_refund) {
      const groupId = body.group_id ?? "";
      if (!groupId) return json({ error: "group_id obrigatório" }, 400);
      const scope = await memberRefundActor(
        admin,
        groupId,
        user.id,
        Boolean(adminRow),
      );
      if (!scope) return json({ error: "not member" }, 403);
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

    const settled: string[] = [];
    for (const groupId of ids) {
      const allowed = await maySettle(
        admin,
        groupId,
        user.id,
        Boolean(adminRow),
      );
      if (!allowed) continue;
      await settleGroup(admin, pagbank, groupId);
      settled.push(groupId);
      if (!body.sweep) {
        const scope = await memberRefundActor(
          admin,
          groupId,
          user.id,
          Boolean(adminRow),
        );
        if (scope) {
          await processMemberRefunds(admin, pagbank, {
            groupId,
            userId: scope.userId,
          });
        }
      }
    }
    if (body.sweep) await processMemberRefunds(admin, pagbank);
    if (!body.sweep && ids.length === 1 && settled.length === 0) {
      return json({ error: "not member" }, 403);
    }
    await pollPendingPagBankCharges(admin, pagbank, Deno.env);
    await retryPendingCustodyReleases(admin, pagbank);
    await runPlatformCac(admin, Deno.env, pagbankCacClient(Deno.env));
    return json({ settled });
  } catch (error) {
    const failure = clientFailure(error, "settle-charges");
    return json(failure.body, failure.status);
  }
}

async function settleUser(
  req: Request,
  authHeader: string,
  deps?: SettleDeps,
): Promise<{ id: string } | null> {
  if (deps && "user" in deps) return deps.user ?? null;
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data } = await userClient.auth.getUser();
  return data.user ? { id: data.user.id } : null;
}

if (import.meta.main) {
  Deno.serve((req) => handleSettle(req));
}
