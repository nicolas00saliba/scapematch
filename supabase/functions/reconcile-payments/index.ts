import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";

type Deps = {
  // deno-lint-ignore no-explicit-any
  admin?: any;
  asaas?: AsaasProvider;
  serviceKey?: string;
};

export async function handleReconcile(
  req: Request,
  deps?: Deps,
): Promise<Response> {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  const service = deps?.serviceKey ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const header = req.headers.get("Authorization") ?? "";
  if (service.length === 0 || header !== `Bearer ${service}`) {
    return json({ error: "not authenticated" }, 401);
  }
  try {
    const admin = deps?.admin ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      service,
    );
    const asaas = deps?.asaas ?? AsaasProvider.fromEnv(Deno.env);
    return json(await reconcilePayments(admin, asaas));
  } catch (_error) {
    return json({ error: "erro" }, 500);
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleReconcile(req));
}
