// Conciliação diária. Só GET no Asaas. Não cria cobrança, estorno nem transferência.

import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";

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
    const window = saoPauloWindow(deps.now ?? new Date());
    const payments = await listPayments(fetchFn, base, apiKey, window);
    const snapshot = await store.rpc("ledger_reconcile_snapshot", {
      p_since: window.sinceIso,
      p_until: window.untilIso,
      p_payment_ids: payments.rows.map((item) => item.id),
      p_transfer_ids: [],
    });
    if (snapshot.error) return json({ error: "indisponivel" }, 500);
    const local = readSnapshot(snapshot.data);
    const filled = await fillMissingPayments(
      fetchFn,
      base,
      apiKey,
      payments,
      local.charges,
    );
    const transfers = await readSubaccountTransfers(
      fetchFn,
      base,
      store,
      window,
      local.withdrawals,
    );
    const divergences = compareLedger({
      payments: filled.rows,
      transfers: transfers.rows,
      charges: local.charges,
      withdrawals: local.withdrawals,
      truncated: filled.truncated || transfers.truncated || local.capped,
      uncheckedChargeRefs: filled.unchecked,
      uncheckedWithdrawalIds: transfers.unchecked,
    });
    const saved = await store.rpc("record_payment_divergences", {
      p_payment_count: filled.rows.length,
      p_transfer_count: transfers.rows.length,
      p_truncated: filled.truncated || transfers.truncated || local.capped,
      p_rows: divergences,
    });
    if (saved.error) return json({ error: "indisponivel" }, 500);
    return json({ ok: true, divergences: divergences.length });
  } catch {
    return json({ error: "indisponivel" }, 500);
  }
}

async function listPayments(
  fetchFn: FetchFn,
  base: string,
  apiKey: string,
  window: { sinceDay: string; untilDay: string },
): Promise<{ rows: RemotePayment[]; truncated: boolean }> {
  const created = await listCollection(
    fetchFn,
    base,
    apiKey,
    "/payments",
    "dateCreated",
    window.sinceDay,
    window.untilDay,
    parsePayment,
  );
  const paid = await listCollection(
    fetchFn,
    base,
    apiKey,
    "/payments",
    "paymentDate",
    window.sinceDay,
    window.untilDay,
    parsePayment,
  );
  const byId = new Map<string, RemotePayment>();
  for (const row of [...created.rows, ...paid.rows]) byId.set(row.id, row);
  return {
    rows: [...byId.values()],
    truncated: created.truncated || paid.truncated,
  };
}

async function fillMissingPayments(
  fetchFn: FetchFn,
  base: string,
  apiKey: string,
  listed: { rows: RemotePayment[]; truncated: boolean },
  charges: LocalCharge[],
): Promise<{
  rows: RemotePayment[];
  truncated: boolean;
  unchecked: Set<string>;
}> {
  const byId = new Map(listed.rows.map((row) => [row.id, row]));
  const unchecked = new Set<string>();
  for (const charge of charges) {
    const ref = charge.providerRef;
    if (ref === "" || byId.has(ref)) continue;
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(ref)) {
      unchecked.add(ref);
      continue;
    }
    const read = await readOne(
      fetchFn,
      `${base}/payments/${ref}`,
      apiKey,
      parsePayment,
    );
    if (read === "missing") continue;
    if (read === "unchecked") {
      unchecked.add(ref);
      continue;
    }
    byId.set(read.id, read);
  }
  return { rows: [...byId.values()], truncated: listed.truncated, unchecked };
}

async function readSubaccountTransfers(
  fetchFn: FetchFn,
  base: string,
  store: Store,
  window: { sinceDay: string; untilDay: string },
  withdrawals: LocalWithdrawal[],
): Promise<{
  rows: RemoteTransfer[];
  truncated: boolean;
  unchecked: Set<string>;
}> {
  const rows: RemoteTransfer[] = [];
  const seen = new Set<string>();
  const unchecked = new Set<string>();
  let truncated = false;
  const byVenue = new Map<string, LocalWithdrawal[]>();
  for (const withdrawal of withdrawals) {
    const venueId = withdrawal.venueId;
    if (!/^[0-9a-f-]{36}$/i.test(venueId)) {
      unchecked.add(withdrawal.id);
      continue;
    }
    const group = byVenue.get(venueId) ?? [];
    group.push(withdrawal);
    byVenue.set(venueId, group);
  }
  for (const [venueId, group] of byVenue) {
    const keyResult = await store.rpc("read_venue_asaas_key", {
      p_venue_id: venueId,
    });
    const apiKey = keyResult.error ? "" : text(keyResult.data).trim();
    if (apiKey === "") {
      for (const withdrawal of group) unchecked.add(withdrawal.id);
      continue;
    }
    const listed = await listCollection(
      fetchFn,
      base,
      apiKey,
      "/transfers",
      "dateCreated",
      window.sinceDay,
      window.untilDay,
      parseTransfer,
    );
    if (listed.truncated) truncated = true;
    for (const transfer of listed.rows) {
      if (seen.has(transfer.id)) continue;
      seen.add(transfer.id);
      rows.push(transfer);
    }
    for (const withdrawal of group) {
      const id = withdrawal.asaasTransferId;
      if (id === "" || seen.has(id)) continue;
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
        unchecked.add(withdrawal.id);
        continue;
      }
      const read = await readOne(
        fetchFn,
        `${base}/transfers/${id}`,
        apiKey,
        parseTransfer,
      );
      if (read === "unchecked") {
        unchecked.add(withdrawal.id);
        continue;
      }
      if (read === "missing") continue;
      seen.add(read.id);
      rows.push(read);
    }
  }
  return { rows, truncated, unchecked };
}

async function readOne<T>(
  fetchFn: FetchFn,
  url: string,
  apiKey: string,
  parse: (row: Record<string, unknown>) => T | null,
): Promise<T | "missing" | "unchecked"> {
  const response = await fetchFn(url, {
    method: "GET",
    redirect: "manual",
    headers: { access_token: apiKey },
  });
  if (response.status === 404) return "missing";
  if (response.status >= 300 && response.status < 400) return "unchecked";
  if (!response.ok) return "unchecked";
  const body = await response.json();
  if (!body || typeof body !== "object") return "unchecked";
  return parse(body as Record<string, unknown>) ?? "unchecked";
}

async function listCollection<T>(
  fetchFn: FetchFn,
  base: string,
  apiKey: string,
  path: "/payments" | "/transfers",
  dateField: "dateCreated" | "paymentDate",
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
      [`${dateField}[ge]`]: since,
      [`${dateField}[le]`]: until,
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
  return { id, status: remotePaymentStatus(row), valueCents };
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
    status: mapTransferStatus(status),
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
    venueId: text(row.venue_id),
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
