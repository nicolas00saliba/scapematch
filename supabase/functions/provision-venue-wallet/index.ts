import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { WooviProvider } from "../_shared/woovi_provider.ts";

/// Cria a subconta Woovi da casa com a chave Pix já salva. Não abre a Woovi.
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
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    const body = await req.json().catch(() => ({})) as {
      venue_id?: string;
      pix_key?: string;
    };
    const venueId = (body.venue_id ?? "").trim();
    if (!adminRow && !venueId) return json({ error: "not admin" }, 403);

    let query = admin
      .from("venues")
      .select("id, owner_id, name, status")
      .eq("status", "approved");
    if (venueId) query = query.eq("id", venueId);
    if (!adminRow) query = query.eq("owner_id", userData.user.id);
    const { data: venues, error } = await query;
    if (error) return json({ error: "erro" }, 400);

    const woovi = WooviProvider.fromEnv(Deno.env);
    const provisioned: { venue_id: string }[] = [];
    for (const venue of venues ?? []) {
      const row = venue as { id: string; name: string };
      let pixKey = (body.pix_key ?? "").trim();
      if (!pixKey) {
        const bank = await admin.rpc("venue_bank_for_transfer", {
          p_venue_id: row.id,
        });
        const stored = bank.data as { pix_key?: string } | null;
        pixKey = (stored?.pix_key ?? "").trim();
      }
      if (!pixKey) return json({ error: "sem pix" }, 409);
      await woovi.createSubaccount({ name: row.name, pixKey });
      const { error: saveError } = await admin.rpc(
        "upsert_provider_payout_account",
        {
          p_venue_id: row.id,
          p_provider: "woovi",
          p_external_id: pixKey,
          p_pix_key: pixKey,
          p_status: "active",
          p_expires_at: null,
          p_auto_withdraw: false,
        },
      );
      if (saveError) return json({ error: "erro" }, 400);
      provisioned.push({ venue_id: row.id });
    }
    return json({ provisioned });
  } catch (error) {
    const failure = clientFailure(error, "provision-venue-wallet");
    return json(failure.body, failure.status);
  }
});
