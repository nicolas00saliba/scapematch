// Não cria subconta. Devolve o link do PagBank Connect. O state é
// aleatório, de uso único, e fica preso ao usuário desta sessão.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import { connectRedirectUri } from "../_shared/pagbank_connect.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { adminWithMfa } from "../_shared/admin_session.ts";

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
    const adminRow = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as {
      venue_id?: string;
      surface?: string;
    };
    const venueId = (body.venue_id ?? "").trim();
    if (!venueId) return json({ error: "venue_id" }, 400);

    const { data: venue, error } = await admin
      .from("venues")
      .select("id, owner_id, status")
      .eq("id", venueId)
      .maybeSingle();
    if (error || !venue) return json({ error: "erro" }, 400);
    if (!adminRow && venue.owner_id !== userData.user.id) {
      return json({ error: "not admin" }, 403);
    }
    if (venue.status !== "approved") return json({ error: "casa" }, 400);

    const clientId = (Deno.env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "").trim();
    const redirect = connectRedirectUri({
      partner: Deno.env.get("PAGBANK_CONNECT_REDIRECT_URI") ?? "",
      admin: Deno.env.get("PAGBANK_CONNECT_ADMIN_REDIRECT_URI") ?? "",
      surface: body.surface === "admin" ? "admin" : "parceiro",
    });
    if (!clientId) return json({ error: "pagbank_connect" }, 500);
    const { data: state, error: stateError } = await admin.rpc(
      "begin_pagbank_connect",
      {
        p_venue_id: venueId,
        p_user_id: userData.user.id,
        p_redirect_uri: redirect,
      },
    );
    const connectState = typeof state === "string" ? state.trim() : "";
    if (stateError || !connectState || connectState === venueId) {
      return json({ error: "state" }, 500);
    }
    const connectUrl = PagBankProvider.fromEnv(Deno.env).connectAuthorizeUrl({
      clientId,
      redirectUri: redirect,
      state: connectState,
    });
    return json({ venue_id: venueId, connect_url: connectUrl });
  } catch (error) {
    logCaught("provision-venue-wallet", error);
    const failure = clientFailure(error, "provision-venue-wallet");
    return json(failure.body, failure.status);
  }
});
