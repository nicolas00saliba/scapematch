// Sonda da API de Cadastro. O cron manda x-pagbank-signup-probe-secret.
// Não cria conta: o corpo é só {"type":"SELLER"}.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { createSecretCache } from "../_shared/cron_secret.ts";
import { handlePagbankSignupProbe } from "../_shared/pagbank_accounts.ts";
import { captureOpsAlert } from "../_shared/sentry_ops.ts";

const secretCache = createSecretCache();

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service);
  return handlePagbankSignupProbe(req, {
    env: Deno.env,
    fetchFn: fetch,
    secretCache,
    readVault: () =>
      admin.rpc("cron_vault_secret", {
        p_name: "pagbank_signup_probe_secret",
      }),
    store: {
      async apply(input) {
        const { data, error } = await admin.rpc("apply_pagbank_signup_probe", {
          p_http: input.http,
          p_code: input.code,
          p_enable: input.enable,
        });
        if (error || !data || typeof data !== "object") throw new Error("erro");
        const row = data as { enabled?: unknown; changed?: unknown };
        return { enabled: row.enabled === true, changed: row.changed === true };
      },
    },
    alert: (code) =>
      captureOpsAlert(Deno.env, fetch, {
        scope: "pagbank-signup-probe",
        code,
      }).then(() => undefined),
  });
});
