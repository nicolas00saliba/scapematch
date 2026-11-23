// Troca o code do PagBank Connect pela conta da casa.
// Grava o account id e o access token. O token não volta na resposta.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
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
      venue_id?: string;
      code?: string;
      state?: string;
    };
    const venueId = (body.venue_id ?? body.state ?? "").trim();
    const code = (body.code ?? "").trim();
    if (!venueId || !code) return json({ error: "code" }, 400);
    const { data: venue, error } = await admin
      .from("venues")
      .select("id, owner_id")
      .eq("id", venueId)
      .maybeSingle();
    if (error || !venue) return json({ error: "erro" }, 400);
    if (!adminRow && venue.owner_id !== userData.user.id) {
      return json({ error: "not admin" }, 403);
    }
    const clientId = (Deno.env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "").trim();
    const clientSecret = (Deno.env.get("PAGBANK_CONNECT_CLIENT_SECRET") ?? "")
      .trim();
    const redirect = (Deno.env.get("PAGBANK_CONNECT_REDIRECT_URI") ?? "").trim();
    if (!clientId || !clientSecret || !redirect.startsWith("https://")) {
      return json({ error: "pagbank_connect" }, 500);
    }
    const exchanged = await PagBankProvider.fromEnv(Deno.env).exchangeConnectCode({
      clientId,
      clientSecret,
      code,
      redirectUri: redirect,
    });
    const { error: updateError } = await admin
      .from("venues")
      .update({ pagbank_account_id: exchanged.accountId })
      .eq("id", venueId);
    if (updateError) return json({ error: "erro" }, 400);
    const { error: keyError } = await admin.rpc("store_venue_provider_key", {
      p_venue_id: venueId,
      p_api_key: exchanged.accessToken,
    });
    if (keyError) return json({ error: "erro" }, 400);
    return json({ venue_id: venueId, linked: true });
  } catch (error) {
    logCaught("pagbank-connect", error);
    const failure = clientFailure(error, "pagbank-connect");
    return json(failure.body, failure.status);
  }
});
