// Conciliação diária. Só GET no Asaas. Não cria cobrança, estorno nem transferência.

import { mapAsaasTransferStatus } from "./asaas_transfers.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";

export type RemotePayment = {
  id: string;
  status: string;
  valueCents: number;
};

export type RemoteTransfer = {
  id: string;
  status: string;
  valueCents: number;
  externalReference: string;
};

export type LocalCharge = {
  id: string;
  providerRef: string;
  status: string;
  amountCents: number;
  ledgerKinds: string[];
};

export type LocalWithdrawal = {
  id: string;
  externalReference: string;
  asaasTransferId: string;
  status: string;
  amountCents: number;
};

export type Divergence = {
  kind: string;
  providerRef: string;
  localId: string;
  expected: string;
  actual: string;
};

const paidLedger = new Set(["house_net", "commission"]);
const refundLedger = new Set(["house_refund", "commission_refund"]);

export function reaisToCents(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  const cents = Math.round(value * 100);
  if (cents <= 0 || cents > 100_000_000) return null;
  return cents;
}

export function mapPaymentStatus(status: string): string {
  switch (status) {
    case "RECEIVED":
    case "CONFIRMED":
    case "RECEIVED_IN_CASH":
      return "paid";
    case "REFUNDED":
      return "refunded";
    case "PENDING":
    case "OVERDUE":
    case "AWAITING_RISK_ANALYSIS":
      return "pending";
    case "DELETED":
      return "cancelled";
    default:
      return /^[A-Z_]{1,40}$/.test(status) ? status : "unknown";
  }
}

export function compareLedger(input: {
  payments: RemotePayment[];
  transfers: RemoteTransfer[];
  charges: LocalCharge[];
  withdrawals: LocalWithdrawal[];
  truncated: boolean;
}): Divergence[] {
  const found: Divergence[] = [];
  const chargesByRef = new Map(
    input.charges
      .filter((row) => row.providerRef !== "")
      .map((row) => [row.providerRef, row]),
  );
  const seenPayments = new Set<string>();

  for (const payment of input.payments) {
    seenPayments.add(payment.id);
    const local = chargesByRef.get(payment.id);
    if (!local) {
      found.push(row("charge_missing_local", payment.id, "", "", payment.status));
      continue;
    }
    if (local.status !== payment.status) {
      found.push(row(
        "charge_status",
        payment.id,
        local.id,
        local.status,
        payment.status,
      ));
    }
    if (local.amountCents !== payment.valueCents) {
      found.push(row(
        "charge_amount",
        payment.id,
        local.id,
        String(local.amountCents),
        String(payment.valueCents),
      ));
    }
  }

  if (!input.truncated) {
    for (const local of input.charges) {
      if (local.providerRef === "" || seenPayments.has(local.providerRef)) {
        continue;
      }
      found.push(row(
        "charge_missing_asaas",
        local.providerRef,
        local.id,
        local.status,
        "",
      ));
    }
  }

  for (const local of input.charges) {
    const kinds = new Set(local.ledgerKinds);
    if (local.status === "paid" && !overlaps(kinds, paidLedger)) {
      found.push(row("ledger_missing", local.providerRef, local.id, "paid", ""));
    }
    if (local.status === "refunded" && !overlaps(kinds, refundLedger)) {
      found.push(row(
        "ledger_refund_missing",
        local.providerRef,
        local.id,
        "refunded",
        "",
      ));
    }
  }

  const withdrawals = input.withdrawals;
  const seenTransfers = new Set<string>();
  for (const transfer of input.transfers) {
    seenTransfers.add(transfer.id);
    if (transfer.externalReference !== "") {
      seenTransfers.add(transfer.externalReference);
    }
    const local = withdrawals.find((item) =>
      item.asaasTransferId === transfer.id ||
      (transfer.externalReference !== "" &&
        item.externalReference === transfer.externalReference)
    );
    if (!local) {
      found.push(row(
        "transfer_missing_local",
        transfer.id,
        "",
        "",
        transfer.status,
      ));
      continue;
    }
    if (local.status !== transfer.status) {
      found.push(row(
        "transfer_status",
        transfer.id,
        local.id,
        local.status,
        transfer.status,
      ));
    }
    if (local.amountCents !== transfer.valueCents) {
      found.push(row(
        "transfer_amount",
        transfer.id,
        local.id,
        String(local.amountCents),
        String(transfer.valueCents),
      ));
    }
  }

  if (!input.truncated) {
    for (const local of withdrawals) {
      if (local.asaasTransferId === "") continue;
      if (
        seenTransfers.has(local.asaasTransferId) ||
        seenTransfers.has(local.externalReference)
      ) {
        continue;
      }
      found.push(row(
        "transfer_missing_asaas",
        local.asaasTransferId,
        local.id,
        local.status,
        "",
      ));
    }
  }

  if (input.truncated) {
    found.push(row("asaas_truncated", "", "", "", ""));
  }
  return found;
}

function overlaps(left: Set<string>, right: Set<string>): boolean {
  for (const item of left) {
    if (right.has(item)) return true;
  }
  return false;
}

function row(
  kind: string,
  providerRef: string,
  localId: string,
  expected: string,
  actual: string,
): Divergence {
  return {
    kind,
    providerRef: clip(providerRef, 80),
    localId: clip(localId, 80),
    expected: clip(expected, 40),
    actual: clip(actual, 40),
  };
}

function clip(value: string, max: number): string {
  return value.length <= max ? value : value.slice(0, max);
}

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

type Store = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
};

export type LedgerDeps = {
  env: EnvLike;
  fetchFn?: FetchFn;
  store?: Store;
};

const pageLimit = 100;
const maxPages = 5;

export async function handleLedgerReconcile(
  req: Request,
  deps: LedgerDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  const secret = deps.env.get("LEDGER_RECONCILE_SECRET") ?? "";
  const header = req.headers.get("x-ledger-reconcile-secret") ?? "";
  if (secret.trim() === "") {
    return json({ error: "config_ausente" }, 503);
  }
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  const base = (deps.env.get("ASAAS_BASE_URL") ?? "").trim().replace(/\/+$/, "");
  const apiKey = (deps.env.get("ASAAS_API_KEY") ?? "").trim();
  if (!base.startsWith("https://") || apiKey === "") {
    return json({ error: "config_ausente" }, 503);
  }
  const fetchFn = deps.fetchFn ?? fetch;
  const store = deps.store;
  if (!store) return json({ error: "indisponivel" }, 500);
  try {
    const since = utcDay(-1);
    const until = utcDay(0);
    const payments = await listCollection(
      fetchFn,
      base,
      apiKey,
      "/payments",
      since,
      until,
      parsePayment,
    );
    const transfers = await listCollection(
      fetchFn,
      base,
      apiKey,
      "/transfers",
      since,
      until,
      parseTransfer,
    );
    const snapshot = await store.rpc("ledger_reconcile_snapshot", {
      p_since: `${since}T00:00:00Z`,
      p_payment_ids: payments.rows.map((item) => item.id),
      p_transfer_ids: transfers.rows.map((item) => item.id),
    });
    if (snapshot.error) return json({ error: "indisponivel" }, 500);
    const local = readSnapshot(snapshot.data);
    const divergences = compareLedger({
      payments: payments.rows,
      transfers: transfers.rows,
      charges: local.charges,
      withdrawals: local.withdrawals,
      truncated: payments.truncated || transfers.truncated || local.capped,
    });
    const saved = await store.rpc("record_payment_divergences", {
      p_payment_count: payments.rows.length,
      p_transfer_count: transfers.rows.length,
      p_truncated: payments.truncated || transfers.truncated || local.capped,
      p_rows: divergences,
    });
    if (saved.error) return json({ error: "indisponivel" }, 500);
    return json({ ok: true, divergences: divergences.length });
  } catch {
    return json({ error: "indisponivel" }, 500);
  }
}

function utcDay(offset: number): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}

async function listCollection<T>(
  fetchFn: FetchFn,
  base: string,
  apiKey: string,
  path: "/payments" | "/transfers",
  since: string,
  until: string,
  parse: (row: Record<string, unknown>) => T | null,
): Promise<{ rows: T[]; truncated: boolean }> {
  const rows: T[] = [];
  let truncated = false;
  for (let page = 0; page < maxPages; page++) {
    const params = new URLSearchParams({
      limit: String(pageLimit),
      offset: String(page * pageLimit),
      "dateCreated[ge]": since,
      "dateCreated[le]": until,
    });
    const url = `${base}${path}?${params}`;
    const response = await fetchFn(url, {
      method: "GET",
      redirect: "manual",
      headers: { access_token: apiKey },
    });
    if (response.status >= 300 && response.status < 400) {
      throw new Error("redirect");
    }
    if (!response.ok) throw new Error("asaas");
    const body = await response.json() as {
      data?: unknown;
      hasMore?: unknown;
    };
    const data = Array.isArray(body.data) ? body.data : [];
    for (const item of data) {
      if (!item || typeof item !== "object") continue;
      const parsed = parse(item as Record<string, unknown>);
      if (parsed) rows.push(parsed);
    }
    const hasMore = body.hasMore === true;
    if (!hasMore) return { rows, truncated };
    if (page === maxPages - 1) truncated = true;
  }
  return { rows, truncated };
}

function parsePayment(row: Record<string, unknown>): RemotePayment | null {
  const id = typeof row.id === "string" ? row.id : "";
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) return null;
  const valueCents = reaisToCents(row.value);
  if (valueCents == null) return null;
  const status = typeof row.status === "string" ? row.status : "";
  return { id, status: mapPaymentStatus(status), valueCents };
}

function parseTransfer(row: Record<string, unknown>): RemoteTransfer | null {
  const id = typeof row.id === "string" ? row.id : "";
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) return null;
  const valueCents = reaisToCents(row.value);
  if (valueCents == null) return null;
  const reference = typeof row.externalReference === "string"
    ? row.externalReference
    : "";
  const safeReference = /^[A-Za-z0-9:_-]{1,80}$/.test(reference) ? reference : "";
  const status = typeof row.status === "string" ? row.status : "";
  return {
    id,
    status: mapAsaasTransferStatus(status),
    valueCents,
    externalReference: safeReference,
  };
}

function readSnapshot(data: unknown): {
  charges: LocalCharge[];
  withdrawals: LocalWithdrawal[];
  capped: boolean;
} {
  const row = data !== null && typeof data === "object"
    ? data as Record<string, unknown>
    : {};
  return {
    charges: Array.isArray(row.charges) ? row.charges.flatMap(readCharge) : [],
    withdrawals: Array.isArray(row.withdrawals)
      ? row.withdrawals.flatMap(readWithdrawal)
      : [],
    capped: row.capped === true,
  };
}

function readCharge(value: unknown): LocalCharge[] {
  if (!value || typeof value !== "object") return [];
  const row = value as Record<string, unknown>;
  const id = text(row.id);
  const providerRef = text(row.provider_ref);
  const status = text(row.status);
  const amount = number(row.amount_cents);
  if (!id || amount == null) return [];
  const kinds = Array.isArray(row.ledger_kinds)
    ? row.ledger_kinds.filter((item): item is string => typeof item === "string")
    : [];
  return [{
    id,
    providerRef,
    status,
    amountCents: amount,
    ledgerKinds: kinds,
  }];
}

function readWithdrawal(value: unknown): LocalWithdrawal[] {
  if (!value || typeof value !== "object") return [];
  const row = value as Record<string, unknown>;
  const id = text(row.id);
  const amount = number(row.amount_cents);
  if (!id || amount == null) return [];
  return [{
    id,
    externalReference: text(row.external_reference),
    asaasTransferId: text(row.asaas_transfer_id),
    status: text(row.status),
    amountCents: amount,
  }];
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

async function secretMatches(header: string, secret: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(header)),
    crypto.subtle.digest("SHA-256", encoder.encode(secret)),
  ]);
  return sameBytes(new Uint8Array(left), new Uint8Array(right)) &&
    secret.length > 0;
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}
