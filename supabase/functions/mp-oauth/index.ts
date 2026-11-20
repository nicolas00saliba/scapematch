import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { handleMpOauth } from "../_shared/mp_oauth.ts";
import { paymentsStack } from "../_shared/payment_provider.ts";

if (import.meta.main) {
  Deno.serve(async (req) => {
    const json = bindJson(req);
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
    }
    if (req.method !== "POST") return json({ error: "method" }, 405);
    if (paymentsStack(Deno.env) !== "woovi") {
      return json({ error: "provider_asaas" }, 409);
    }
    const header = req.headers.get("Authorization") ?? "";
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: header } } },
    );
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) return json({ error: "not authenticated" }, 401);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const result = await handleMpOauth(req, {
      env: Deno.env,
      store: {
        async rpc(fn, args) {
          const response = await admin.rpc(fn, args);
          if (response.error) throw new Error(response.error.message);
          return response.data;
        },
      },
    }, data.user.id);
    return json(result.body, result.status);
  });
}
