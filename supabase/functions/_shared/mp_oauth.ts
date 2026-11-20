// Conexão OAuth da casa com o Mercado Pago. O client_secret não sai
// da função. O token fica cifrado no banco, pelo RPC, e não volta
// na resposta. O state amarra a casa sem guardar sessão.

import { timingSafeEqualText } from "./payment_provider.ts";
import {
  exchangeAuthorizationCode,
  mpAuthorizationUrl,
  oauthExpiresAt,
} from "./mercadopago_provider.ts";
import type { EnvLike } from "./http.ts";
import type { FetchLike } from "./payment_provider.ts";

type Store = {
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
};

export type OauthDeps = {
  env: EnvLike;
  store: Store;
  fetchFn?: FetchLike;
  now?: Date;
};

export async function handleMpOauth(
  req: Request,
  deps: OauthDeps,
  actorId: string,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  const action = text(body?.action);
  const venueId = text(body?.venue_id);
  if (!isUuid(venueId)) return { status: 400, body: { error: "valor" } };
  const allowed = await deps.store.rpc("provider_actor_can_manage", {
    p_venue_id: venueId,
    p_actor: actorId,
  });
  if (allowed !== true) return { status: 403, body: { error: "not owner" } };
  if (action === "start") return start(deps, venueId);
  if (action === "callback") {
    return callback(deps, venueId, text(body?.code), text(body?.state));
  }
  return { status: 400, body: { error: "valor" } };
}

async function start(
  deps: OauthDeps,
  venueId: string,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const clientId = env(deps, "MP_CLIENT_ID");
  const redirect = env(deps, "MP_OAUTH_REDIRECT_URI");
  const secret = stateSecret(deps);
  if (!clientId || !redirect || secret.length < 16) {
    return { status: 503, body: { error: "config_ausente" } };
  }
  const state = await signState(venueId, secret);
  return {
    status: 200,
    body: {
      url: mpAuthorizationUrl({ clientId, redirectUri: redirect, state }),
      state,
    },
  };
}

async function callback(
  deps: OauthDeps,
  venueId: string,
  code: string,
  state: string,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const secret = stateSecret(deps);
  const expected = await signState(venueId, secret);
  if (!code || !timingSafeEqualText(state, expected)) {
    return { status: 401, body: { error: "unauthorized" } };
  }
  const token = await exchangeAuthorizationCode({
    clientId: env(deps, "MP_CLIENT_ID"),
    clientSecret: env(deps, "MP_CLIENT_SECRET"),
    code,
    redirectUri: env(deps, "MP_OAUTH_REDIRECT_URI"),
    now: deps.now,
  }, deps.fetchFn);
  await deps.store.rpc("store_provider_oauth", {
    p_venue_id: venueId,
    p_provider: "mercadopago",
    p_access_token: token.accessToken,
    p_refresh_token: token.refreshToken,
    p_expires_at: token.expiresAt || oauthExpiresAt(deps.now ?? new Date()).toISOString(),
  });
  await deps.store.rpc("upsert_provider_payout_account", {
    p_venue_id: venueId,
    p_provider: "mercadopago",
    p_external_id: "mercadopago",
    p_pix_key: "",
    p_status: "active",
    p_expires_at: token.expiresAt,
    p_auto_withdraw: false,
  });
  return {
    status: 200,
    body: { ok: true, provider: "mercadopago", connected: true },
  };
}

export async function signState(venueId: string, secret: string): Promise<string> {
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
    new TextEncoder().encode(venueId),
  );
  const hex = [...new Uint8Array(signed)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return `${venueId}.${hex}`;
}

function stateSecret(deps: OauthDeps): string {
  return env(deps, "MP_OAUTH_STATE_SECRET") || env(deps, "MP_CLIENT_SECRET");
}

function env(deps: OauthDeps, name: string): string {
  try {
    return (deps.env.get(name) ?? "").trim();
  } catch {
    return "";
  }
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(value);
}
