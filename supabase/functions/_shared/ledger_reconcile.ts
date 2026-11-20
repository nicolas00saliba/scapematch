// Conciliação diária. O cron autenticado não consulta provedor.

import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";
import { resolveCronSecret, type SecretCache } from "./cron_secret.ts";
import { secretMatches } from "./venue_payouts.ts";

export type RemotePayment = {
  id: string;
  status: string | null;
  valueCents: number;
};

export type RemoteTransfer = {
  id: string;
  status: string | null;
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
  venueId: string;
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

/// null = o Asaas mandou um status que o livro não tem.
export function mapPaymentStatus(status: string): string | null {
  switch (status.trim().toUpperCase()) {
    case "PENDING":
    case "OVERDUE":
    case "AWAITING_RISK_ANALYSIS":
    case "DUNNING_REQUESTED":
      return "pending";
    case "AUTHORIZED":
      return "authorized";
    case "RECEIVED":
    case "CONFIRMED":
    case "RECEIVED_IN_CASH":
    case "DUNNING_RECEIVED":
      return "paid";
    case "REFUNDED":
    case "REFUND_REQUESTED":
    case "REFUND_IN_PROGRESS":
      return "refunded";
    case "DELETED":
    case "CANCELED":
    case "CANCELLED":
      return "cancelled";
    default:
      return null;
  }
}

/// Pix apagado volta deleted:true e status PENDING. Isso é cancelamento.
export function remotePaymentStatus(
  row: Record<string, unknown>,
): string | null {
  if (row.deleted === true) return "cancelled";
  const status = typeof row.status === "string" ? row.status : "";
  return mapPaymentStatus(status);
}

/// null = status de transferência fora do livro. Não vira "pending".
export function mapTransferStatus(status: string): string | null {
  switch (status.trim().toUpperCase()) {
    case "PENDING":
    case "BANK_PROCESSING":
      return "pending";
    case "DONE":
      return "done";
    case "CANCELLED":
      return "cancelled";
    case "FAILED":
      return "failed";
    default:
      return null;
  }
}

export function saoPauloWindow(now: Date): {
  sinceDay: string;
  untilDay: string;
  sinceIso: string;
  untilIso: string;
} {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
  }).format(now);
  const sinceDay = shiftIsoDate(today, -1);
  const nextDay = shiftIsoDate(today, 1);
  return {
    sinceDay,
    untilDay: today,
    sinceIso: saoPauloMidnightUtc(sinceDay),
    untilIso: saoPauloMidnightUtc(nextDay),
  };
}

function shiftIsoDate(day: string, days: number): string {
  const [year, month, date] = day.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, date + days)).toISOString()
    .slice(0, 10);
}

function saoPauloMidnightUtc(day: string): string {
  const [year, month, date] = day.split("-").map(Number);
  for (let hour = 0; hour < 8; hour++) {
    const instant = new Date(Date.UTC(year, month - 1, date, hour, 0, 0));
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Sao_Paulo",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      hourCycle: "h23",
    }).formatToParts(instant);
    const value = (type: string) =>
      parts.find((part) => part.type === type)?.value ?? "";
    const monthText = String(month).padStart(2, "0");
    const dateText = String(date).padStart(2, "0");
    if (
      value("year") === String(year) &&
      value("month") === monthText &&
      value("day") === dateText &&
      value("hour") === "00"
    ) {
      return instant.toISOString();
    }
  }
  return new Date(Date.UTC(year, month - 1, date, 3, 0, 0)).toISOString();
}

export function compareLedger(input: {
  payments: RemotePayment[];
  transfers: RemoteTransfer[];
  charges: LocalCharge[];
  withdrawals: LocalWithdrawal[];
  truncated: boolean;
  uncheckedChargeRefs?: ReadonlySet<string>;
  uncheckedWithdrawalIds?: ReadonlySet<string>;
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
      found.push(row(
        "charge_missing_local",
        payment.id,
        "",
        "",
        payment.status ?? "",
      ));
      continue;
    }
    if (payment.status == null) {
      found.push(row(
        "charge_status_unknown",
        payment.id,
        local.id,
        local.status,
        "",
      ));
    } else if (!chargeStatusesMatch(local, payment.status)) {
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
    const uncheckedCharges = input.uncheckedChargeRefs ?? new Set<string>();
    for (const local of input.charges) {
      if (local.providerRef === "" || seenPayments.has(local.providerRef)) {
        continue;
      }
      if (uncheckedCharges.has(local.providerRef)) continue;
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
    if (
      local.status === "refunded" &&
      overlaps(kinds, paidLedger) &&
      !overlaps(kinds, refundLedger)
    ) {
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
        transfer.status ?? "",
      ));
      continue;
    }
    if (transfer.status == null) {
      found.push(row(
        "transfer_status_unknown",
        transfer.id,
        local.id,
        local.status,
        "",
      ));
    } else if (local.status !== transfer.status) {
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
    const unchecked = input.uncheckedWithdrawalIds ?? new Set<string>();
    for (const local of withdrawals) {
      if (unchecked.has(local.id)) continue;
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

/// Pré-autorização cancelada: o Asaas estorna e devolve REFUNDED.
/// O livro grava cancelled porque o valor não foi capturado.
function chargeStatusesMatch(local: LocalCharge, remote: string): boolean {
  if (local.status === remote) return true;
  return local.status === "cancelled" &&
    remote === "refunded" &&
    !overlaps(new Set(local.ledgerKinds), paidLedger);
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
  now?: Date;
  secretCache?: SecretCache;
};

export async function handleLedgerReconcile(
  req: Request,
  deps: LedgerDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  const header = req.headers.get("x-ledger-reconcile-secret") ?? "";
  const secret = await resolveCronSecret({
    envValue: deps.env.get("LEDGER_RECONCILE_SECRET"),
    vaultName: "ledger_reconcile_secret",
    cache: deps.secretCache,
    now: deps.now?.getTime(),
    readVault: deps.store
      ? async () => {
        const result = await deps.store!.rpc("cron_vault_secret", {
          p_name: "ledger_reconcile_secret",
        });
        if (result.error) return "";
        return result.data;
      }
      : undefined,
  });
  if (secret === "") {
    return json({ error: "config_ausente" }, 503);
  }
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  // O provedor antigo saiu. O cron autenticado não consulta API nenhuma.
  return json({ ok: true, skipped: true, divergences: 0 });
}
