import { handleLedgerReconcile } from "../_shared/ledger_reconcile.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

if (import.meta.main) {
  Deno.serve((req) =>
    handleLedgerReconcile(req, {
      env: Deno.env,
      store: {
        rpc(name, args) {
          const admin = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          );
          return admin.rpc(name, args);
        },
      },
    })
  );
}
