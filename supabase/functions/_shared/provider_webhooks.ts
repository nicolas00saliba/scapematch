// Webhooks da Woovi e do Mercado Pago. A assinatura é conferida antes
// de qualquer gravação. O evento entra uma vez: a segunda entrega
// responde ok e não muda o livro.

import { logCaught } from "./client_error.ts";
import { bandConfirmed } from "./group_band.ts";
import { applyPaymentTransition } from "./ledger.ts";
import {
  mpPlatformFallback,
  mpSignatureMatches,
  mpWebhookManifest,
  parseSignatureHeader,
} from "./mercadopago_provider.ts";
import {
  groupUnconfirmedNotice,
  readEnv,
  timingSafeEqualText,
  type FetchLike,
} from "./payment_provider.ts";
import { wooviEventStatus } from "./woovi_provider.ts";
import type { EnvLike } from "./http.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

type Json = Record<string, unknown>;

export type WebhookDeps = {
  env: EnvLike;
  admin: Admin;
  rawBody?: string;
  publicKeys?: string[];
  fetchFn?: FetchLike;
};

export async function handleWooviWebhook(
  req: Request,
  deps: WebhookDeps,
): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const raw = deps.rawBody ?? await req.text();
  const secret = readEnv(deps.env, "WOOVI_WEBHOOK_SECRET");
  const keys = deps.publicKeys ?? pemList(readEnv(deps.env, "WOOVI_WEBHOOK_PUBLIC_KEY"));
  const ok = await verifyWooviWebhook({
    rawBody: raw,
    hmacHeader: req.headers.get("x-openpix-signature"),
    rsaHeader: req.headers.get("x-webhook-signature"),
    secret,
    publicKeys: keys,
  });
  if (!ok) return json({ error: "unauthorized" }, 401);
  let payload: Json;
  try {
    payload = JSON.parse(raw) as Json;
  } catch {
    return json({ error: "payload" }, 400);
  }
  const event = text(payload.event);
  const next = wooviEventStatus(event);
  const charge = record(payload.charge);
  const pix = record(payload.pix);
  const correlation = text(charge.correlationID);
  if (!next || !correlation) return json({ ok: true });
  const eventId = `${event}:${correlation}:${text(pix.endToEndId)}`;
  const claimed = await claimEvent(deps.admin, "woovi", eventId);
  if (claimed === "duplicate") return json({ ok: true, duplicate: true });
  try {
    const row = await findCharge(deps.admin, correlation, "woovi");
    if (!row) return json({ ok: true });
    if (text(pix.endToEndId)) {
      await deps.admin.from("payment_charges").update({
        provider_end_to_end_id: text(pix.endToEndId),
      }).eq("id", row.id);
    }
    const credit = next === "paid" && await groupConfirmed(deps.admin, row.group_id);
    await applyPaymentTransition(deps.admin, row.id, next, credit);
    return json({ ok: true, notice: groupUnconfirmedNotice });
  } catch (error) {
    await releaseEvent(deps.admin, "woovi", eventId);
    logCaught("woovi-webhook", error);
    return json({ error: "erro" }, 500);
  }
}

export async function handleMpWebhook(
  req: Request,
  deps: WebhookDeps,
): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const raw = deps.rawBody ?? await req.text();
  const secret = readEnv(deps.env, "MP_WEBHOOK_SECRET");
  const url = new URL(req.url);
  const dataId = url.searchParams.get("data.id") ?? "";
  const signature = parseSignatureHeader(req.headers.get("x-signature"));
  const requestId = req.headers.get("x-request-id") ?? "";
  const manifest = mpWebhookManifest({
    dataId,
    requestId,
    ts: signature.ts,
  });
  const ok = await mpSignatureMatches({
    secret,
    manifest,
    v1: signature.v1,
  });
  if (!ok) return json({ error: "unauthorized" }, 401);
  let payload: Json;
  try {
    payload = JSON.parse(raw) as Json;
  } catch {
    return json({ error: "payload" }, 400);
  }
  const data = record(payload.data);
  const paymentId = dataId || text(data.id);
  if (!paymentId) return json({ ok: true });
  const eventId = text(payload.id) || `${text(payload.action)}:${paymentId}`;
  const claimed = await claimEvent(deps.admin, "mercadopago", eventId);
  if (claimed === "duplicate") return json({ ok: true, duplicate: true });
  try {
    const row = await findCharge(deps.admin, paymentId, "mercadopago");
    if (!row) return json({ ok: true });
    const { MercadoPagoProvider } = await import("./mercadopago_provider.ts");
    const token = await houseToken(deps, row.venue_id);
    const remote = await MercadoPagoProvider.fromEnv(deps.env, deps.fetchFn).getPayment(
      paymentId,
      token,
    );
    const credit = remote.status === "paid" &&
      await groupConfirmed(deps.admin, row.group_id);
    if (remote.status === "pending") {
      await releaseEvent(deps.admin, "mercadopago", eventId);
      return json({ ok: true, pending: true });
    }
    await applyPaymentTransition(deps.admin, row.id, remote.status, credit);
    return json({ ok: true });
  } catch (error) {
    await releaseEvent(deps.admin, "mercadopago", eventId);
    logCaught("mp-webhook", error);
    return json({ error: "erro" }, 500);
  }
}

export async function verifyWooviWebhook(input: {
  rawBody: string;
  hmacHeader: string | null;
  rsaHeader: string | null;
  secret: string;
  publicKeys: string[];
}): Promise<boolean> {
  const secret = input.secret.trim();
  const keys = input.publicKeys.map((key) => key.trim()).filter(Boolean);
  if (!secret && keys.length === 0) return false;
  if (secret && input.hmacHeader && await hmacMatches(input.rawBody, input.hmacHeader, secret)) {
    return true;
  }
  if (keys.length > 0 && input.rsaHeader && await rsaMatches(input.rawBody, input.rsaHeader, keys)) {
    return true;
  }
  return false;
}

async function hmacMatches(raw: string, header: string, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(raw),
  );
  const hex = [...new Uint8Array(signed)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return timingSafeEqualText(hex, header.trim().toLowerCase());
}

async function rsaMatches(
  raw: string,
  signature: string,
  pems: string[],
): Promise<boolean> {
  const data = new TextEncoder().encode(raw);
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(signature.trim()), (char) => char.charCodeAt(0));
  } catch {
    return false;
  }
  for (const pem of pems) {
    try {
      const key = await crypto.subtle.importKey(
        "spki",
        pemToDer(pem),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"],
      );
      const copy = new Uint8Array(bytes);
      if (await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, copy, data)) {
        return true;
      }
    } catch {
      continue;
    }
  }
  return false;
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PUBLIC KEY-----/g, "")
    .replace(/-----END PUBLIC KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function pemList(value: string): string[] {
  if (!value.trim()) return [];
  return [value];
}

async function releaseEvent(
  admin: Admin,
  provider: string,
  eventId: string,
): Promise<void> {
  try {
    await admin.rpc("release_provider_webhook", {
      p_provider: provider,
      p_event_id: eventId,
    });
  } catch (error) {
    logCaught("provider-webhook", error);
  }
}

async function claimEvent(
  admin: Admin,
  provider: string,
  eventId: string,
): Promise<"new" | "duplicate"> {
  const { data, error } = await admin.rpc("claim_provider_webhook", {
    p_provider: provider,
    p_event_id: eventId,
  });
  if (error) throw new Error("idempotencia");
  return data === true ? "new" : "duplicate";
}

async function findCharge(
  admin: Admin,
  providerRef: string,
  provider: string,
): Promise<{ id: string; group_id: string; venue_id: string } | null> {
  const { data } = await admin.from("payment_charges")
    .select("id, group_id, venue_id, provider")
    .eq("provider_ref", providerRef)
    .maybeSingle();
  if (!data || data.provider !== provider) return null;
  return {
    id: text(data.id),
    group_id: text(data.group_id),
    venue_id: text(data.venue_id),
  };
}

async function houseToken(deps: WebhookDeps, venueId: string): Promise<string> {
  try {
    const loaded = await deps.admin.rpc("read_provider_oauth", {
      p_venue_id: venueId,
      p_provider: "mercadopago",
    });
    const token = loaded?.data?.access_token;
    if (typeof token === "string" && token.trim()) return token.trim();
  } catch (error) {
    logCaught("mp-webhook", error);
  }
  const fallback = mpPlatformFallback(deps.env);
  if (fallback) return fallback;
  console.error(JSON.stringify({
    scope: "mp-webhook",
    code: "oauth_da_casa_ausente",
  }));
  throw new Error("oauth da casa ausente");
}

async function groupConfirmed(admin: Admin, groupId: string): Promise<boolean> {
  const { data: group } = await admin.from("groups")
    .select("cancelled_at, confirmed_at, closed_at, closes_at, total_spots, minimum_spots")
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return false;
  const { count } = await admin.from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return bandConfirmed(group, count ?? 0);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function record(value: unknown): Json {
  return value && typeof value === "object" ? value as Json : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}
