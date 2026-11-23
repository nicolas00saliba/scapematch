// Prontidão dos pagamentos. Cada campo é sim ou não.
// Nenhum valor de segredo, URL ou e-mail sai daqui.

import { pagbankProductionBaseUrl } from "./pagbank_provider.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";
import { logCaught } from "./pagbank_client_error.ts";

export function secretPresent(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

/// Só a base oficial de produção, sem barra no fim. Sandbox e vazio são não.
export function pagbankBaseUrlIsProduction(value: string | undefined): boolean {
  const normalized = (value ?? "").trim().replace(/\/+$/, "");
  return normalized === pagbankProductionBaseUrl;
}

const failureCodes = new Set(["config_ausente", "cron_failed"]);

export type ReadinessReport = {
  pagbank_api_key: boolean;
  pagbank_base_url_production: boolean;
  pagbank_webhook_token: boolean;
  pagbank_webhook_email: boolean;
  venue_withdrawals_secret: boolean;
  ledger_reconcile_secret: boolean;
  vault_venue_withdrawals_url: boolean;
  vault_venue_withdrawals_secret: boolean;
  vault_ledger_reconcile_secret: boolean;
  venue_payouts_enabled: boolean;
  cron_last_failed: boolean | null;
  cron_failure_code: string | null;
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
    pagbank_api_key: secretPresent(env.get("PAGBANK_TOKEN")),
    pagbank_base_url_production: pagbankBaseUrlIsProduction(
      env.get("PAGBANK_BASE_URL"),
    ),
    pagbank_webhook_token: secretPresent(env.get("PAGBANK_WEBHOOK_SECRET")),
    pagbank_webhook_email: secretPresent(env.get("PAGBANK_WEBHOOK_EMAIL")),
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
