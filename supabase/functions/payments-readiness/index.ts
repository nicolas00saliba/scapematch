import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { handlePaymentsReadiness } from "../_shared/payments_readiness.ts";

if (import.meta.main) {
  Deno.serve((req) =>
    handlePaymentsReadiness(req, {
      env: Deno.env,
      loadVault: () => loadVault(req),
    })
  );
}

async function loadVault(req: Request): Promise<unknown> {
  const header = req.headers.get("Authorization") ?? "";
  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: header } } },
  );
  const { data, error } = await client.rpc("admin_payments_readiness");
  if (error) throw new Error(error.message);
  return data;
}
