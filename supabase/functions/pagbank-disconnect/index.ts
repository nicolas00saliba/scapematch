// Desconecta a conta PagBank da casa. É o único caminho para trocar de conta:
// desconectar e conectar de novo. A conta e o token ficam no servidor, presos
// à casa. Dono (com confirmação na tela) ou Admin com MFA; recusa com 409 se
// houver dinheiro a caminho. A resposta leva só os 4 últimos caracteres.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { adminWithMfa } from "../_shared/admin_session.ts";
import {
  conflictBody,
  conflictFromRpc,
  ownerMayDisconnect,
} from "../_shared/pagbank_binding.ts";

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "not authenticated" }, 401);
    }
    const admin = createClient(url, service);
    const { data: adminLookup } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    const isAdmin = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as { venue_id?: string };
    const venueId = (body.venue_id ?? "").trim();
    if (!venueId) return json({ error: "venue_id" }, 400);
    if (!isAdmin && !ownerMayDisconnect) {
      return json({ error: "not admin" }, 403);
    }
    const { data, error } = await admin.rpc("disconnect_venue_pagbank", {
      p_venue_id: venueId,
      p_actor: userData.user.id,
      p_admin: Boolean(isAdmin),
    });
    if (error) {
      const conflict = conflictFromRpc(error);
      if (conflict) return json(conflictBody(conflict), 409);
      if ((error.message ?? "").includes("not owner")) {
        return json({ error: "not owner" }, 403);
      }
      throw new Error("erro");
    }
    const row = (data ?? {}) as { disconnected?: boolean };
    return json({ disconnected: row.disconnected === true });
  } catch (error) {
    logCaught("pagbank-disconnect", error);
    const failure = clientFailure(error, "pagbank-disconnect");
    return json(failure.body, failure.status);
  }
});
