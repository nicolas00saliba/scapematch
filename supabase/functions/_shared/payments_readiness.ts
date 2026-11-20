// Prontidão dos pagamentos. Cada campo é sim ou não.
// Nenhum valor de segredo, URL ou e-mail sai daqui.

import { asaasProductionBaseUrl } from "./asaas_provider.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";
import { logCaught } from "./asaas_client_error.ts";
import { mpAccessTokenIsTest } from "./mercadopago_provider.ts";
import { paymentsStack, type PaymentsStack } from "./payment_provider.ts";
import { isWooviSandbox, wooviSandboxBaseUrl } from "./woovi_provider.ts";

export function secretPresent(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

/// Só a base oficial de produção, sem barra no fim. Sandbox e vazio são não.
export function asaasBaseUrlIsProduction(value: string | undefined): boolean {
  const normalized = (value ?? "").trim().replace(/\/+$/, "");
  return normalized === asaasProductionBaseUrl;
}

const failureCodes = new Set(["config_ausente", "cron_failed"]);

export type ReadinessReport = {
  asaas_api_key: boolean;
  asaas_base_url_production: boolean;
  asaas_webhook_token: boolean;
  asaas_webhook_email: boolean;
  venue_withdrawals_secret: boolean;
  ledger_reconcile_secret: boolean;
  vault_venue_withdrawals_url: boolean;
  vault_venue_withdrawals_secret: boolean;
  vault_ledger_reconcile_secret: boolean;
  venue_payouts_enabled: boolean;
  cron_last_failed: boolean | null;
  cron_failure_code: string | null;
  payments_provider: PaymentsStack;
  woovi_app_id: boolean;
  woovi_base_url_sandbox: boolean;
  woovi_webhook_secret: boolean;
  woovi_webhook_public_key: boolean;
  mp_client_id: boolean;
  mp_client_secret: boolean;
  mp_webhook_secret: boolean;
  mp_oauth_redirect_uri: boolean;
  mp_access_token_test: boolean;
};

export function buildReadiness(env: EnvLike, vault: unknown): ReadinessReport {
  const row = vault !== null && typeof vault === "object"
    ? vault as Record<string, unknown>
    : {};
  const code = typeof row.cron_failure_code === "string" &&
      failureCodes.has(row.cron_failure_code)
    ? row.cron_failure_code
    : null;
  const failed = row.cron_last_failed === true
    ? true
    : row.cron_last_failed === false
    ? false
    : null;
  return {
    asaas_api_key: secretPresent(env.get("ASAAS_API_KEY")),
    asaas_base_url_production: asaasBaseUrlIsProduction(
      env.get("ASAAS_BASE_URL"),
    ),
    asaas_webhook_token: secretPresent(env.get("ASAAS_WEBHOOK_TOKEN")),
    asaas_webhook_email: secretPresent(env.get("ASAAS_WEBHOOK_EMAIL")),
    venue_withdrawals_secret: secretPresent(
      env.get("VENUE_WITHDRAWALS_SECRET"),
    ) || row.vault_venue_withdrawals_secret === true,
    ledger_reconcile_secret: secretPresent(
      env.get("LEDGER_RECONCILE_SECRET"),
    ) || row.vault_ledger_reconcile_secret === true,
    vault_venue_withdrawals_url: row.vault_venue_withdrawals_url === true,
    vault_venue_withdrawals_secret: row.vault_venue_withdrawals_secret === true,
    vault_ledger_reconcile_secret: row.vault_ledger_reconcile_secret === true,
    venue_payouts_enabled: row.venue_payouts_enabled === true,
    cron_last_failed: failed,
    cron_failure_code: failed === true ? code : null,
    payments_provider: paymentsStack(env),
    woovi_app_id: secretPresent(env.get("WOOVI_APP_ID")),
    woovi_base_url_sandbox: isWooviSandbox(
      (env.get("WOOVI_BASE_URL") ?? "").trim() || wooviSandboxBaseUrl,
    ),
    woovi_webhook_secret: secretPresent(env.get("WOOVI_WEBHOOK_SECRET")),
    woovi_webhook_public_key: secretPresent(env.get("WOOVI_WEBHOOK_PUBLIC_KEY")),
    mp_client_id: secretPresent(env.get("MP_CLIENT_ID")),
    mp_client_secret: secretPresent(env.get("MP_CLIENT_SECRET")),
    mp_webhook_secret: secretPresent(env.get("MP_WEBHOOK_SECRET")),
    mp_oauth_redirect_uri: secretPresent(env.get("MP_OAUTH_REDIRECT_URI")),
    mp_access_token_test: mpAccessTokenIsTest(env.get("MP_ACCESS_TOKEN")),
  };
}

export type ReadinessDeps = {
  env: EnvLike;
  loadVault: () => Promise<unknown>;
};

export async function handlePaymentsReadiness(
  req: Request,
  deps: ReadinessDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "method" }, 405);
  }
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer \S+$/i.test(auth)) {
    return json({ error: "not authenticated" }, 401);
  }
  let vault: unknown;
  try {
    vault = await deps.loadVault();
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (
      /not authenticated|not admin|mfa obrigatorio|permission denied/i.test(
        message,
      )
    ) {
      return json({ error: "forbidden" }, 403);
    }
    logCaught("payments-readiness", error);
    return json({ error: "indisponivel" }, 500);
  }
  return json(buildReadiness(deps.env, vault));
}
