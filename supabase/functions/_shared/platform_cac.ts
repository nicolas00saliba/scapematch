// Complemento que o split não alcança. A custódia só libera o que o
// cliente pagou. O resto sai da conta da EscapeMatch por P2P, na API
// segura, depois que a custódia da reserva foi liberada.
// https://developer.pagbank.com.br/reference/criar-transferencia
// A chamada real só existe com PAGBANK_CAC_TRANSFERS=on. Qualquer outro
// valor, inclusive vazio, não fala com o PagBank.

import {
  pagbankProductionBaseUrl,
  pagbankSandboxBaseUrl,
  type PagBankFetch,
} from "./pagbank_provider.ts";

export const maxCacAttempts = 8;

export type CacEnv = { get(name: string): string | undefined };

export type CacClaim = {
  id: string;
  payment_charge_id: string;
  venue_id: string;
  amount_cents: number;
  attempts: number;
  account_id: string | null;
};

export type CacTransferClient = {
  notificationUrl: string;
  balanceCents(): Promise<number | null>;
  postTransfer(
    body: Record<string, unknown>,
    idempotencyKey: string,
  ): Promise<{ status: number; body: unknown }>;
};

type CacRpc = (
  fn: string,
  args: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message: string } | null }>;

function readEnv(env: CacEnv, name: string): string {
  try {
    return (env.get(name) ?? "").trim();
  } catch {
    return "";
  }
}

export function cacTransfersEnabled(env: CacEnv): boolean {
  return readEnv(env, "PAGBANK_CAC_TRANSFERS") === "on";
}

/// O POST /transfers P2P não usa o host de pedidos.
export function secureTransferBase(apiBase: string): string {
  const base = apiBase.trim().replace(/\/$/, "");
  if (base === pagbankSandboxBaseUrl) return "https://secure.sandbox.api.pagseguro.com";
  if (base === pagbankProductionBaseUrl) return "https://secure.api.pagseguro.com";
  throw new Error("fora da API PagBank");
}

export function cacReference(chargeId: string): string {
  const compact = chargeId.replace(/-/g, "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(compact)) throw new Error("cobranca");
  return `cac${compact}`;
}

export function cacTransferBody(input: {
  chargeId: string;
  amountCents: number;
  accountId: string;
  notificationUrl: string;
}): Record<string, unknown> {
  if (!Number.isInteger(input.amountCents) || input.amountCents <= 0) {
    throw new Error("valor");
  }
  const account = input.accountId.trim();
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(account)) throw new Error("conta");
  const url = input.notificationUrl.trim();
  if (!url.startsWith("https://")) throw new Error("sem aviso");
  return {
    amount: { value: input.amountCents, currency: "BRL" },
    reference_id: cacReference(input.chargeId),
    description: "Complemento EscapeMatch",
    instrument: { type: "P2P", p2p: { account_id: account } },
    notification_urls: [url],
  };
}

export function cacOutcome(
  status: number,
  body: unknown,
): "paid" | "saldo" | "failed" {
  const text = JSON.stringify(body ?? "").toLowerCase();
  if (
    status === 402 ||
    text.includes("insufficient") ||
    text.includes("saldo")
  ) {
    return "saldo";
  }
  if (status < 200 || status >= 300) return "failed";
  if (!body || typeof body !== "object") return "failed";
  const record = body as Record<string, unknown>;
  const id = typeof record.id === "string" ? record.id : "";
  if (!id) return "failed";
  const transferStatus = typeof record.status === "string" ? record.status : "";
  if (
    transferStatus === "FAILED" ||
    transferStatus === "CANCELED" ||
    transferStatus === "CANCELLED"
  ) {
    return "failed";
  }
  return "paid";
}

export function alertPlatformCac(input: { chargeId: string; code: string }): void {
  const charge = /^[0-9a-f-]{36}$/i.test(input.chargeId) ? input.chargeId : "invalid";
  const code = /^[a-z_]{1,40}$/.test(input.code) ? input.code : "failed";
  console.error(JSON.stringify({ scope: "platform_cac", code, charge }));
}

function claimsOf(data: unknown): CacClaim[] {
  if (!Array.isArray(data)) return [];
  const rows: CacClaim[] = [];
  for (const item of data) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    const id = typeof row.id === "string" ? row.id : "";
    const charge = typeof row.payment_charge_id === "string"
      ? row.payment_charge_id
      : "";
    const venue = typeof row.venue_id === "string" ? row.venue_id : "";
    const amount = Number(row.amount_cents);
    const attempts = Number(row.attempts);
    if (!id || !charge || !venue) continue;
    if (!Number.isInteger(amount) || amount <= 0) continue;
    if (!Number.isInteger(attempts) || attempts < 1) continue;
    rows.push({
      id,
      payment_charge_id: charge,
      venue_id: venue,
      amount_cents: amount,
      attempts,
      account_id: typeof row.account_id === "string" ? row.account_id : null,
    });
  }
  return rows;
}

/// Não chama a rede quando a flag está desligada. Com a flag ligada,
/// saldo curto ou conta ausente não disparam o POST.
export async function runPlatformCac(
  admin: { rpc: CacRpc },
  env: CacEnv,
  client: CacTransferClient,
): Promise<{ sent: number; failed: number }> {
  if (!cacTransfersEnabled(env)) return { sent: 0, failed: 0 };
  const listed = await admin.rpc("claim_platform_cac", { p_limit: 20 });
  if (listed.error) return { sent: 0, failed: 0 };
  const rows = claimsOf(listed.data);
  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    const outcome = await sendOne(admin, client, row);
    if (outcome === "paid") sent += 1;
    else failed += 1;
  }
  return { sent, failed };
}

async function sendOne(
  admin: { rpc: CacRpc },
  client: CacTransferClient,
  row: CacClaim,
): Promise<"paid" | "failed"> {
  const account = (row.account_id ?? "").trim();
  if (!account) {
    await finish(admin, row, "failed", "", "sem_conta");
    return "failed";
  }
  if (!client.notificationUrl.startsWith("https://")) {
    await finish(admin, row, "failed", "", "sem_aviso");
    return "failed";
  }
  const balance = await client.balanceCents();
  if (balance !== null && balance < row.amount_cents) {
    await finish(admin, row, "failed", "", "saldo");
    return "failed";
  }
  try {
    const body = cacTransferBody({
      chargeId: row.payment_charge_id,
      amountCents: row.amount_cents,
      accountId: account,
      notificationUrl: client.notificationUrl,
    });
    const response = await client.postTransfer(body, cacReference(row.payment_charge_id));
    const outcome = cacOutcome(response.status, response.body);
    if (outcome === "paid") {
      const id = response.body && typeof response.body === "object"
        ? String((response.body as { id?: unknown }).id ?? "")
        : "";
      await finish(admin, row, "paid", id, "");
      return "paid";
    }
    await finish(admin, row, "failed", "", outcome === "saldo" ? "saldo" : "pagbank");
    return "failed";
  } catch {
    await finish(admin, row, "failed", "", "pagbank");
    return "failed";
  }
}

async function finish(
  admin: { rpc: CacRpc },
  row: CacClaim,
  status: "paid" | "failed",
  providerRef: string,
  error: string,
): Promise<void> {
  await admin.rpc("complete_platform_cac", {
    p_id: row.id,
    p_status: status,
    p_provider_ref: providerRef,
    p_error: error,
  });
  if (status === "failed") {
    alertPlatformCac({
      chargeId: row.payment_charge_id,
      code: row.attempts >= maxCacAttempts ? "esgotado" : (error || "failed"),
    });
  }
}

export function pagbankCacClient(
  env: CacEnv,
  fetchFn: PagBankFetch = fetch,
): CacTransferClient {
  const token = readEnv(env, "PAGBANK_TOKEN");
  const api = readEnv(env, "PAGBANK_ENV").toLowerCase() === "sandbox"
    ? pagbankSandboxBaseUrl
    : pagbankProductionBaseUrl;
  const secure = secureTransferBase(api);
  const project = readEnv(env, "SUPABASE_URL").replace(/\/$/, "");
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
    "User-Agent": "EscapeMatch",
  };
  return {
    notificationUrl: project.startsWith("https://")
      ? `${project}/functions/v1/pagbank-webhook`
      : "",
    async balanceCents() {
      if (!token) return null;
      const response = await fetchFn(`${api}/accounts/balance`, {
        method: "GET",
        headers,
      });
      if (!response.ok) return null;
      const body = await response.json().catch(() => null);
      if (!body || typeof body !== "object") return null;
      const record = body as Record<string, unknown>;
      if (typeof record.balance === "number" && Number.isFinite(record.balance)) {
        return Number.isInteger(record.balance)
          ? record.balance
          : Math.round(record.balance * 100);
      }
      const amount = record.amount;
      if (amount && typeof amount === "object") {
        const value = (amount as { value?: unknown }).value;
        if (typeof value === "number" && Number.isInteger(value)) return value;
      }
      return null;
    },
    async postTransfer(body, idempotencyKey) {
      const response = await fetchFn(`${secure}/transfers`, {
        method: "POST",
        headers: {
          ...headers,
          "Content-Type": "application/json",
          "x-idempotency-key": idempotencyKey,
        },
        body: JSON.stringify(body),
      });
      const payload = await response.json().catch(() => null);
      return { status: response.status, body: payload };
    },
  };
}
