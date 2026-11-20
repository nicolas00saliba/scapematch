// Saque da casa pela subconta Woovi. A casa não abre a Woovi.
// O saldo do provedor sai em woovi_balance. O extrato local continua no snapshot.

import { clientFailure } from "./client_error.ts";
import { resolveCronSecret, type SecretCache } from "./cron_secret.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";
import {
  wooviHouseBalance,
  wooviHouseWithdraw,
  wooviScheduledReport,
} from "./provider_house.ts";

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
  "sem pix",
  "minimo",
  "agenda",
];

export type Amr = { method?: string; timestamp?: number };

export type AuthClaims = { aal?: string; amr?: Amr[] };

export type PayoutActor = { id: string; email: string };

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
  fetchFn?: typeof fetch;
  nowSec?: number;
  today?: string;
  secretCache?: SecretCache;
};

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
  const message = error instanceof Error ? error.message : "";
  for (const code of knownErrors) {
    if (message.includes(code)) return code;
  }
  return "erro";
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
    if (action === "woovi_balance") {
      return json(await wooviHouseBalance(deps, venueId, actor.id));
    }
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
    if (action === "woovi_withdraw" || action === "withdraw") {
      const amount = integerOrNull(body?.amount_cents);
      if (amount == null || amount <= 0) return json({ error: "valor" }, 400);
      const result = await wooviHouseWithdraw(deps, {
        venueId,
        actorId: actor.id,
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

export async function handleScheduledWithdrawals(
  req: Request,
  deps: PayoutDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  const header = req.headers.get("x-venue-withdrawals-secret") ?? "";
  const secret = await resolveCronSecret({
    envValue: deps.env.get("VENUE_WITHDRAWALS_SECRET"),
    vaultName: "venue_withdrawals_secret",
    cache: deps.secretCache,
    now: deps.nowSec == null ? undefined : deps.nowSec * 1000,
    readVault: () =>
      deps.store.rpc("cron_vault_secret", {
        p_name: "venue_withdrawals_secret",
      }),
  });
  if (secret === "") {
    return json({ error: "config_ausente" }, 503);
  }
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  return json(wooviScheduledReport());
}

async function loadSnapshot(
  deps: PayoutDeps,
  actor: PayoutActor,
  claims: AuthClaims,
  venueId: string,
): Promise<Record<string, unknown>> {
  const asAdmin = claims.aal === "aal2" && await deps.store.isAdmin(actor.id);
  return record(await deps.store.rpc("venue_payout_snapshot", {
    p_venue_id: venueId,
    p_actor: actor.id,
    p_as_admin: asAdmin,
  })) ?? { enabled: false, can_withdraw: false };
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
