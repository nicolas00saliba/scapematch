import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { handleMpWebhook } from "../_shared/provider_webhooks.ts";

if (import.meta.main) {
  Deno.serve((req) =>
    handleMpWebhook(req, {
      env: Deno.env,
      admin: createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      ),
    })
  );
}
