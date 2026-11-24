// Cria a conta SELLER quando a flag está ligada. O CPF não volta na resposta
// e não é gravado. Com a flag desligada a função não chama a PagBank.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { adminWithMfa } from "../_shared/admin_session.ts";
import { handlePagbankSignup } from "../_shared/pagbank_accounts.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service);
  return handlePagbankSignup(req, {
    env: Deno.env,
    fetchFn: fetch,
    now: () => new Date(),
    store: {
      async actor(authHeader) {
        const userClient = createClient(url, anon, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data, error } = await userClient.auth.getUser();
        if (error || !data.user) return null;
        const { data: row } = await admin
          .from("admins")
          .select("user_id")
          .eq("user_id", data.user.id)
          .maybeSingle();
        return {
          id: data.user.id,
          admin: adminWithMfa(Boolean(row), authHeader),
        };
      },
      async venue(id) {
        const { data } = await admin
          .from("venues")
          .select("id, owner_id, status")
          .eq("id", id)
          .maybeSingle();
        if (!data?.id) return null;
        return {
          id: String(data.id),
          ownerId: String(data.owner_id ?? ""),
          status: String(data.status ?? ""),
        };
      },
      async apiEnabled() {
        const { data, error } = await admin.rpc("pagbank_signup_api_enabled");
        if (error) throw new Error("erro");
        return data === true;
      },
      async existingAccount(venueId) {
        const { data, error } = await admin.rpc("venue_pagbank_account_id", {
          p_venue_id: venueId,
        });
        if (error) throw new Error("erro");
        return typeof data === "string" && data.trim() ? data.trim() : null;
      },
      async saveAccount(input) {
        const { error } = await admin.rpc("save_venue_pagbank_signup", {
          p_venue_id: input.venueId,
          p_document_kind: input.documentKind,
          p_business_category: input.businessCategory,
          p_account_id: input.accountId,
          p_account_status: input.status,
        });
        if (error) throw new Error("erro");
      },
    },
  });
});
