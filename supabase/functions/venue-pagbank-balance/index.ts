// Saldo da conta PagBank da casa. O token OAuth não sai desta função.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { adminWithMfa } from "../_shared/admin_session.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { handleVenuePagbankBalance } from "../_shared/venue_pagbank_balance.ts";

if (import.meta.main) {
  Deno.serve((req) => {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const admin = createClient(url, service);
    return handleVenuePagbankBalance(req, {
      env: Deno.env,
      userFrom: async (authHeader) => {
        const userClient = createClient(url, anon, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data, error } = await userClient.auth.getUser();
        if (error || !data.user) return null;
        return { id: data.user.id };
      },
      isAdmin: async (userId, authHeader) => {
        const { data } = await admin
          .from("admins")
          .select("user_id")
          .eq("user_id", userId)
          .maybeSingle();
        return adminWithMfa(Boolean(data), authHeader);
      },
      ownerOf: async (venueId) => {
        const { data } = await admin
          .from("venues")
          .select("owner_id")
          .eq("id", venueId)
          .maybeSingle();
        const owner = data?.owner_id;
        return typeof owner === "string" ? owner : null;
      },
      readTokens: async (venueId) => {
        const { data, error } = await admin.rpc("read_venue_pagbank_tokens", {
          p_venue_id: venueId,
        });
        if (error || !data || typeof data !== "object") return null;
        const row = data as {
          access_token?: string;
          refresh_token?: string;
          access_expires_at?: string | null;
        };
        const accessToken = (row.access_token ?? "").trim();
        if (!accessToken) return null;
        return {
          accessToken,
          refreshToken: (row.refresh_token ?? "").trim(),
          expiresAt: row.access_expires_at ?? null,
        };
      },
      storeTokens: async (venueId, tokens) => {
        const { error } = await admin.rpc("store_venue_pagbank_tokens", {
          p_venue_id: venueId,
          p_access_token: tokens.accessToken,
          p_refresh_token: tokens.refreshToken,
          p_expires_at: tokens.expiresAt,
        });
        if (error) throw new Error("token_store");
      },
      refresh: async (refreshToken) => {
        const clientId = (Deno.env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "")
          .trim();
        const clientSecret = (Deno.env.get("PAGBANK_CONNECT_CLIENT_SECRET") ??
          "").trim();
        if (!clientId || !clientSecret) throw new Error("pagbank_connect");
        const next = await PagBankProvider.fromEnv(Deno.env).refreshConnectToken({
          clientId,
          clientSecret,
          refreshToken,
        });
        return {
          accessToken: next.accessToken,
          refreshToken: next.refreshToken,
          expiresIn: next.expiresIn,
        };
      },
    });
  });
}
