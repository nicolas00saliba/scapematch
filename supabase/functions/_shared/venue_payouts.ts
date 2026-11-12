// Saque da casa. A apiKey da subconta e a ASAAS_API_KEY não saem daqui.
// A Reserva de pontos não é casa: wallet ou chave iguais às dela param o fluxo.

import { clientFailure, logCaught, storedFailure } from "./asaas_client_error.ts";
import { AsaasProvider, asaasSandboxBaseUrl, tokensMatch } from "./asaas_provider.ts";
import {
  isPointsReserve,
  mapTransferEvent,
  mergeReceivables,
  requestFromBank,
  type EnvLike,
  type TransferRequest,
  type TransferResult,
} from "./asaas_transfers.ts";
import { bindJson, corsHeadersFor, todayInSaoPaulo } from "./http.ts";

const reauthWindowSec = 300;

const knownErrors = [
  "titularidade",
  "saldo",
  "bloqueado",
  "saques desligados",
  "not owner",
  "valor",
  "sem subconta",
  "sem conta",
  "minimo",
  "agenda",
];

export type Amr = { method?: string; timestamp?: number };

export type AuthClaims = { aal?: string; amr?: Amr[] };

export type PayoutActor = { id: string; email: string };

export type ReceivableView = {
  cents: number;
  creditDate: string;
  description: string;
};

export type TransferClient = {
  balanceCents(): Promise<number>;
  receivables(today: string): Promise<ReceivableView[]>;
  findTransfer(externalReference: string): Promise<TransferResult | null>;
  createTransfer(input: TransferRequest): Promise<TransferResult>;
};

export type PayoutStore = {
  actor(jwt: string): Promise<PayoutActor | null>;
  verifiedTotp(userId: string): Promise<boolean>;
  isAdmin(userId: string): Promise<boolean>;
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
  ownerEmail(userId: string): Promise<string>;
};

export type PayoutDeps = {
  env: EnvLike;
  store: PayoutStore;
  clientFor(apiKey: string): TransferClient;
  fetchFn?: typeof fetch;
  nowSec?: number;
  today?: string;
};

type Subaccount =
  | { kind: "ok"; client: TransferClient }
  | { kind: "reserve" }
  | { kind: "missing" };

export function recentStrongAuth(
  claims: AuthClaims,
  hasTotp: boolean,
  nowSec: number,
): "ok" | "reauth" | "mfa" {
  const fresh = (method: string) =>
    (claims.amr ?? []).some((item) => {
      const timestamp = Number(item.timestamp);
      return item.method === method &&
        Number.isFinite(timestamp) &&
        timestamp <= nowSec &&
        nowSec - timestamp <= reauthWindowSec;
    });
  if (hasTotp) {
    if (claims.aal === "aal2" && fresh("totp")) return "ok";
    return "mfa";
  }
  if (fresh("password") || fresh("otp")) return "ok";
  return "reauth";
}

export function readJwtClaims(jwt: string): AuthClaims & { sub: string } {
  const part = jwt.split(".")[1] ?? "";
  if (!part) return { sub: "" };
  try {
    const json = JSON.parse(decodeBase64Url(part)) as Record<string, unknown>;
    const amr = Array.isArray(json.amr)
      ? json.amr.filter((item) => item && typeof item === "object") as Amr[]
      : [];
    return {
      sub: typeof json.sub === "string" ? json.sub : "",
      aal: typeof json.aal === "string" ? json.aal : "",
      amr,
    };
  } catch {
    return { sub: "" };
  }
}

export function publicCode(error: unknown): string {
  const text = error instanceof Error ? error.message : "";
  for (const code of knownErrors) {
    if (text.includes(code)) return code;
  }
  return "erro";
}

export function payoutProvider(env: EnvLike, apiKey: string): AsaasProvider {
  const base = (env.get("ASAAS_BASE_URL") ?? asaasSandboxBaseUrl)
    .replace(/\/$/, "");
  return new AsaasProvider(apiKey, base);
}

export function transferClient(provider: AsaasProvider): TransferClient {
  return {
    balanceCents: () => provider.financeBalanceCents(),
    async receivables(today: string) {
      const [payments, movements] = await Promise.all([
        provider.confirmedReceivables(),
        provider.financialTransactions(),
      ]);
      return mergeReceivables(payments, movements, today);
    },
    findTransfer: (externalReference) => provider.findTransfer(externalReference),
    createTransfer: (input) => provider.createTransfer(input),
  };
}

export async function secretMatches(
  header: string,
  secret: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(header)),
    crypto.subtle.digest("SHA-256", encoder.encode(secret)),
  ]);
  return sameBytes(new Uint8Array(left), new Uint8Array(right)) &&
    secret.length > 0;
}

export async function handleVenuePayouts(
  req: Request,
  deps: PayoutDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const body = await req.json().catch(() => null) as
      | Record<string, unknown>
      | null;
    const action = text(body?.action);
    const venueId = text(body?.venue_id);
    if (!isUuid(venueId)) return json({ error: "valor" }, 400);
    const jwt = bearer(req);
    const actor = await deps.store.actor(jwt);
    if (!actor) return json({ error: "not authenticated" }, 401);
    const claims = readJwtClaims(jwt);
    if (action === "snapshot") {
      return json(await loadSnapshot(deps, actor, claims, venueId));
    }
    const gate = recentStrongAuth(
      claims,
      await deps.store.verifiedTotp(actor.id),
      deps.nowSec ?? Math.floor(Date.now() / 1000),
    );
    if (gate !== "ok") return json({ error: gate }, 401);
    if (action === "save_bank") {
      const notice = await deps.store.rpc("save_venue_bank_account", {
        p_venue_id: venueId,
        p_actor: actor.id,
        p_destination: text(body?.destination),
        p_pix_key: text(body?.pix_key),
        p_pix_key_type: text(body?.pix_key_type),
        p_bank_code: text(body?.bank_code),
        p_agency: text(body?.agency),
        p_account_number: text(body?.account_number),
        p_account_digit: text(body?.account_digit),
        p_owner_name: text(body?.owner_name),
        p_owner_document: text(body?.owner_document),
        p_operation_type: text(body?.operation_type),
      });
      await deliverNotice(deps, notice);
      return json(await loadSnapshot(deps, actor, claims, venueId));
    }
    if (action === "save_schedule") {
      await deps.store.rpc("save_venue_payout_schedule", {
        p_venue_id: venueId,
        p_actor: actor.id,
        p_enabled: body?.enabled === true,
        p_frequency: text(body?.frequency),
        p_weekday: integerOrNull(body?.weekday),
        p_min_amount_cents: integerOrNull(body?.min_amount_cents) ?? -1,
      });
      return json(await loadSnapshot(deps, actor, claims, venueId));
    }
    if (action === "withdraw") {
      const amount = integerOrNull(body?.amount_cents);
      if (amount == null || amount <= 0) return json({ error: "valor" }, 400);
      const result = await sendWithdrawal(deps, {
        venueId,
        actorId: actor.id,
        source: "manual",
        periodKey: "",
        amountCents: amount,
      });
      return json(result.body, result.status);
    }
    return json({ error: "valor" }, 400);
  } catch (error) {
    const code = publicCode(error);
    if (code !== "erro") {
      return json({ error: code }, code === "valor" ? 400 : 403);
    }
    const failure = clientFailure(error, "venue-payouts");
    return json(failure.body, failure.status);
  }
}

export async function handleTransferWebhook(
  req: Request,
  deps: PayoutDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const expected = deps.env.get("ASAAS_WEBHOOK_TOKEN");
  if (!tokensMatch(req.headers.get("asaas-access-token"), expected)) {
    return json({ error: "unauthorized" }, 401);
  }
  try {
    const payload = await req.json().catch(() => null) as {
      event?: string;
      transfer?: Record<string, unknown>;
    } | null;
    const status = mapTransferEvent(payload?.event ?? "");
    if (!status || !payload?.transfer) return json({ ok: true });
    const transfer = payload.transfer;
    const applied = await deps.store.rpc("apply_transfer_event", {
      p_external_reference: text(transfer.externalReference),
      p_transfer_id: text(transfer.id),
      p_status: status,
      p_receipt: text(transfer.transactionReceiptUrl),
      p_reason: text(transfer.failReason).slice(0, 80),
    });
    await deliverNotice(deps, record(applied)?.notice_id);
    return json({ ok: true });
  } catch (error) {
    const failure = clientFailure(error, "asaas-transfer-webhook");
    return json(failure.body, failure.status);
  }
}

export async function handleScheduledWithdrawals(
  req: Request,
  deps: PayoutDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  const secret = deps.env.get("VENUE_WITHDRAWALS_SECRET") ?? "";
  const header = req.headers.get("x-venue-withdrawals-secret") ?? "";
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  try {
    const enabled = await deps.store.rpc("venue_payouts_enabled", {});
    if (enabled !== true) return json({ ok: true, created: 0 });
    const due = asRows(await deps.store.rpc("list_due_venue_payouts", {}));
    let created = 0;
    for (const row of due) {
      try {
        const venueId = text(row.venue_id);
        const pending = Number(row.pending_cents) || 0;
        const min = Number(row.min_amount_cents) || 0;
        const keys = await subaccount(deps, venueId);
        if (keys.kind !== "ok") continue;
        const balance = await keys.client.balanceCents();
        const amount = balance - pending;
        if (amount <= 0 || amount < min) continue;
        const result = await sendWithdrawal(deps, {
          venueId,
          actorId: null,
          source: "automatic",
          periodKey: text(row.period_key),
          amountCents: amount,
          balanceCents: balance,
          keys,
        });
        if (result.body.created === true) created += 1;
      } catch (error) {
        logCaught("schedule-venue-withdrawals", error);
      }
    }
    await flushNotices(deps);
    return json({ ok: true, created });
  } catch (error) {
    const failure = clientFailure(error, "schedule-venue-withdrawals");
    return json(failure.body, failure.status);
  }
}

type SendInput = {
  venueId: string;
  actorId: string | null;
  source: "manual" | "automatic";
  periodKey: string;
  amountCents: number;
  balanceCents?: number;
  keys?: Subaccount;
};

async function sendWithdrawal(
  deps: PayoutDeps,
  input: SendInput,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const keys = input.keys ?? await subaccount(deps, input.venueId);
  if (keys.kind === "reserve") return { status: 403, body: { error: "reserva" } };
  if (keys.kind !== "ok") return { status: 403, body: { error: "sem subconta" } };
  const balance = input.balanceCents ?? await keys.client.balanceCents();
  const claimed = record(await deps.store.rpc("claim_venue_withdrawal", {
    p_venue_id: input.venueId,
    p_actor: input.actorId,
    p_source: input.source,
    p_period_key: input.periodKey,
    p_amount_cents: input.amountCents,
    p_available_cents: balance,
  }));
  const id = text(claimed?.id);
  const cents = Number(claimed?.amount_cents);
  if (!isUuid(id) || !Number.isInteger(cents) || cents <= 0) {
    return { status: 400, body: { error: "valor" } };
  }
  const send = await deps.store.rpc("begin_withdrawal_dispatch", { p_id: id });
  if (send !== true) return { status: 200, body: { ok: true, duplicate: true } };
  try {
    const bank = record(await deps.store.rpc("venue_bank_for_transfer", {
      p_venue_id: input.venueId,
    }));
    if (!bank) throw new Error("sem conta");
    const existing = await keys.client.findTransfer(id);
    const transfer = existing ?? await keys.client.createTransfer(
      requestFromBank(bank, cents, id),
    );
    await deps.store.rpc("attach_venue_transfer", {
      p_id: id,
      p_transfer_id: transfer.id,
      p_status: transfer.status,
      p_receipt: transfer.receiptUrl,
    });
    return {
      status: 200,
      body: {
        ok: true,
        id,
        status: transfer.status,
        created: existing == null,
      },
    };
  } catch (error) {
    const reason = storedFailure("venue-payouts", error);
    await deps.store.rpc("fail_venue_withdrawal", {
      p_id: id,
      p_reason: reason,
    }).catch(() => undefined);
    const code = publicCode(error);
    if (code !== "erro") return { status: 403, body: { error: code } };
    return { status: 502, body: { error: "asaas_unavailable" } };
  }
}

async function loadSnapshot(
  deps: PayoutDeps,
  actor: PayoutActor,
  claims: AuthClaims,
  venueId: string,
): Promise<Record<string, unknown>> {
  const asAdmin = claims.aal === "aal2" && await deps.store.isAdmin(actor.id);
  const snap = record(await deps.store.rpc("venue_payout_snapshot", {
    p_venue_id: venueId,
    p_actor: actor.id,
    p_as_admin: asAdmin,
  })) ?? { enabled: false, can_withdraw: false };
  if (snap.enabled !== true) return snap;
  const role = text(snap.role);
  if (role !== "owner" && role !== "partner" && role !== "admin") return snap;
  const keys = await subaccount(deps, venueId);
  if (keys.kind !== "ok") {
    return { ...snap, available_cents: 0, receivables: [] };
  }
  const today = deps.today ?? todayInSaoPaulo();
  const [available, receivables] = await Promise.all([
    keys.client.balanceCents(),
    keys.client.receivables(today),
  ]);
  return { ...snap, available_cents: available, receivables };
}

async function subaccount(
  deps: PayoutDeps,
  venueId: string,
): Promise<Subaccount> {
  const wallet = text(await deps.store.rpc("venue_payout_wallet", {
    p_venue_id: venueId,
  }));
  if (isPointsReserve(deps.env, wallet, "")) return { kind: "reserve" };
  const apiKey = text(await deps.store.rpc("read_venue_asaas_key", {
    p_venue_id: venueId,
  }));
  if (!apiKey) return { kind: "missing" };
  if (isPointsReserve(deps.env, wallet, apiKey)) return { kind: "reserve" };
  return { kind: "ok", client: deps.clientFor(apiKey) };
}

async function deliverNotice(deps: PayoutDeps, notice: unknown): Promise<void> {
  const id = typeof notice === "string" ? notice : text(record(notice)?.id);
  if (!isUuid(id)) return;
  const row = record(await deps.store.rpc("payout_notice", { p_id: id }));
  if (!row || row.sent_at) return;
  const owner = text(row.owner_id);
  const email = owner ? await deps.store.ownerEmail(owner) : "";
  const result = await sendPayoutMail(deps, {
    to: email,
    subject: subjectFor(text(row.kind)),
    text: text(row.body),
  });
  if (result === "sent") {
    await deps.store.rpc("mark_payout_notice_sent", { p_id: id });
  }
}

async function flushNotices(deps: PayoutDeps): Promise<void> {
  const rows = asRows(await deps.store.rpc("unsent_payout_notices", {}));
  for (const row of rows) await deliverNotice(deps, text(row.id));
}

export async function sendPayoutMail(
  deps: { env: EnvLike; fetchFn?: typeof fetch },
  input: { to: string; subject: string; text: string },
): Promise<"sent" | "unconfigured" | "failed"> {
  const key = deps.env.get("RESEND_API_KEY") ?? "";
  const from = deps.env.get("PAYOUT_MAIL_FROM") ?? "";
  if (!key || !from || !input.to.includes("@")) return "unconfigured";
  const fetchFn = deps.fetchFn ?? fetch;
  const response = await fetchFn("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [input.to],
      subject: input.subject,
      text: input.text,
    }),
  });
  return response.ok ? "sent" : "failed";
}

function subjectFor(kind: string): string {
  if (kind === "withdrawal_done") return "Saque concluído no EscapeMatch";
  if (kind === "withdrawal_failed") return "Saque não concluído no EscapeMatch";
  return "Conta de saque alterada no EscapeMatch";
}

function bearer(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function integerOrNull(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  return null;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(value);
}

function record(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function asRows(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item) => item && typeof item === "object") as Record<
    string,
    unknown
  >[];
}

function decodeBase64Url(value: string): string {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (value.length % 4)) % 4);
  return atob(padded);
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}
