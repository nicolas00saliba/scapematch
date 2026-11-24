// Troca o code do PagBank Connect. O state tem de ser o que esta sessão
// pediu, ainda não usado e dentro do prazo. O token não volta na resposta.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import { completePagbankConnect } from "../_shared/pagbank_connect.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { adminWithMfa } from "../_shared/admin_session.ts";

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
    const adminRow = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as {
      code?: string;
      state?: string;
    };
    const code = (body.code ?? "").trim();
    const state = (body.state ?? "").trim();
    if (!code || !state) return json({ error: "code" }, 400);
    const clientId = (Deno.env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "").trim();
    const clientSecret = (Deno.env.get("PAGBANK_CONNECT_CLIENT_SECRET") ?? "")
      .trim();
    if (!clientId || !clientSecret) {
      return json({ error: "pagbank_connect" }, 500);
    }
    const userId = userData.user.id;
    const done = await completePagbankConnect({
      userId,
      code,
      state,
      consume: async (connectState, ownerId) => {
        const { data, error } = await admin.rpc("consume_pagbank_connect", {
          p_state: connectState,
          p_user_id: ownerId,
        });
        const rows = Array.isArray(data) ? data : data ? [data] : [];
        if (error || rows.length === 0) return null;
        const row = rows[0] as { venue_id?: string; redirect_uri?: string };
        const venueId = (row.venue_id ?? "").trim();
        const redirectUri = (row.redirect_uri ?? "").trim();
        if (!venueId) return null;
        if (!adminRow) {
          const { data: venue } = await admin
            .from("venues")
            .select("owner_id")
            .eq("id", venueId)
            .maybeSingle();
          if (venue?.owner_id !== userId) return null;
        }
        return { venueId, redirectUri };
      },
      exchange: (authCode, redirectUri) =>
        PagBankProvider.fromEnv(Deno.env).exchangeConnectCode({
          clientId,
          clientSecret,
          code: authCode,
          redirectUri,
        }),
      saveAccount: async (venueId, accountId) => {
        const { error } = await admin
          .from("venues")
          .update({ pagbank_account_id: accountId })
          .eq("id", venueId);
        if (error) throw new Error("erro");
      },
      saveTokens: async (venueId, tokens) => {
        const { error } = await admin.rpc("store_venue_pagbank_tokens", {
          p_venue_id: venueId,
          p_access_token: tokens.accessToken,
          p_refresh_token: tokens.refreshToken,
          p_expires_at: tokens.expiresAt,
        });
        if (error) throw new Error("erro");
      },
    });
    return json({ venue_id: done.venueId, linked: true });
  } catch (error) {
    logCaught("pagbank-connect", error);
    const failure = clientFailure(error, "pagbank-connect");
    return json(failure.body, failure.status);
  }
});
