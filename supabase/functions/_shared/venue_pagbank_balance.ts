// Saldo PagBank da casa. O access token fica no servidor.
// 401, 403 e 404 não viram número: a tela mostra indisponível e o livro.

import { freshConnectAccess } from "./pagbank_connect.ts";
import { pagbankApiBaseUrl, type PagBankFetch } from "./pagbank_provider.ts";
import { readSellerBalance } from "./pagbank_transfers.ts";
import { bindJson, corsHeadersFor } from "./http.ts";

export const venuePagbankBalanceScope = "venue-pagbank-balance";

type EnvLike = { get(name: string): string | undefined };

export type VenueAccess = {
  accessToken: string;
  refreshToken: string;
  expiresAt: string | null;
};

export type RefreshedAccess = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
};

export type VenuePagbankBalanceDeps = {
  env: EnvLike;
  fetchFn?: PagBankFetch;
  nowMs?: number;
  userFrom(authHeader: string): Promise<{ id: string } | null>;
  isAdmin(userId: string, authHeader: string): Promise<boolean>;
  ownerOf(venueId: string): Promise<string | null>;
  readTokens(venueId: string): Promise<VenueAccess | null>;
  storeTokens(venueId: string, tokens: VenueAccess): Promise<void>;
  refresh(refreshToken: string): Promise<RefreshedAccess>;
};

type BalanceRead = {
  status: number;
  body: Record<string, unknown> | null;
};

export async function handleVenuePagbankBalance(
  req: Request,
  deps: VenuePagbankBalanceDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const user = await deps.userFrom(authHeader);
    if (!user) return json({ error: "not authenticated" }, 401);
    const body = await req.json().catch(() => ({})) as { venue_id?: string };
    const venueId = (body.venue_id ?? "").trim();
    if (!venueId) return json({ error: "venue" }, 400);
    const owner = await deps.ownerOf(venueId);
    if (!owner) return json({ error: "venue" }, 404);
    if (owner !== user.id && !await deps.isAdmin(user.id, authHeader)) {
      return json({ error: "forbidden" }, 403);
    }
    const stored = await deps.readTokens(venueId);
    if (!stored?.accessToken) return json({ status: "unlinked" });
    const balance = await loadVenueBalance(deps, venueId, stored);
    return json(balance);
  } catch (_error) {
    logBalance("internal");
    return json({ status: "unavailable", code: "pagbank_balance_unavailable" });
  }
}

async function loadVenueBalance(
  deps: VenuePagbankBalanceDeps,
  venueId: string,
  stored: VenueAccess,
): Promise<Record<string, unknown>> {
  const nowMs = deps.nowMs ?? Date.now();
  const expiresAtMs = stored.expiresAt ? Date.parse(stored.expiresAt) : null;
  let access = stored.accessToken;
  let refreshToken = stored.refreshToken;
  try {
    const fresh = await freshConnectAccess({
      accessToken: access,
      refreshToken,
      expiresAtMs: Number.isFinite(expiresAtMs) ? expiresAtMs : null,
      nowMs,
      refresh: () => deps.refresh(refreshToken),
    });
    access = fresh.accessToken;
    refreshToken = fresh.refreshToken;
    if (fresh.refreshed) {
      await remember(deps, venueId, access, refreshToken, fresh.expiresAtMs);
    }
  } catch (_error) {
    logBalance("refresh_failed");
    return unavailable();
  }

  const base = pagbankApiBaseUrl(deps.env);
  const url = `${base}/accounts/balance`;
  let read = await getBalance(url, access, deps.fetchFn ?? fetch);
  if (read.status === 401 && refreshToken) {
    try {
      const next = await deps.refresh(refreshToken);
      access = next.accessToken;
      refreshToken = next.refreshToken || refreshToken;
      const expiresAtMs = next.expiresIn > 0
        ? nowMs + next.expiresIn * 1000
        : null;
      await remember(deps, venueId, access, refreshToken, expiresAtMs);
      read = await getBalance(url, access, deps.fetchFn ?? fetch);
    } catch (_error) {
      logBalance("refresh_failed");
      return unavailable();
    }
  }
  if (read.status === 401 || read.status === 403 || read.status === 404) {
    logBalance("pagbank_balance_unavailable", read.status);
    return unavailable();
  }
  if (read.status !== 200 || !read.body) {
    logBalance("pagbank_balance_unavailable", read.status);
    return unavailable();
  }
  try {
    const parsed = readSellerBalance(read.body);
    if (!parsed.exact) logBalance("balance_shape", 200);
    return {
      status: "ok",
      available_cents: parsed.availableCents,
      blocked_cents: parsed.blockedCents,
      held_cents: parsed.heldCents,
    };
  } catch (_error) {
    logBalance("balance_shape", 200);
    return unavailable();
  }
}

function unavailable(): Record<string, unknown> {
  return { status: "unavailable", code: "pagbank_balance_unavailable" };
}

async function remember(
  deps: VenuePagbankBalanceDeps,
  venueId: string,
  accessToken: string,
  refreshToken: string,
  expiresAtMs: number | null,
): Promise<void> {
  try {
    await deps.storeTokens(venueId, {
      accessToken,
      refreshToken,
      expiresAt: expiresAtMs == null ? null : new Date(expiresAtMs).toISOString(),
    });
  } catch (_error) {
    logBalance("token_store_failed");
  }
}

async function getBalance(
  url: string,
  accessToken: string,
  fetchFn: PagBankFetch,
): Promise<BalanceRead> {
  let response: Response;
  try {
    response = await fetchFn(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "User-Agent": "EscapeMatch",
      },
    });
  } catch (_error) {
    return { status: 0, body: null };
  }
  if (!response.ok) {
    await response.body?.cancel?.().catch(() => undefined);
    return { status: response.status, body: null };
  }
  const text = await response.text();
  try {
    const parsed = JSON.parse(text) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { status: 200, body: null };
    }
    return { status: 200, body: parsed as Record<string, unknown> };
  } catch (_error) {
    return { status: 200, body: null };
  }
}

function logBalance(code: string, status?: number): void {
  console.error(JSON.stringify({
    scope: venuePagbankBalanceScope,
    code,
    ...(status == null ? {} : { status: String(status) }),
  }));
}
