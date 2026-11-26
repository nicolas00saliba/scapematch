/// PagBank Connect. O state não é o id da casa: o banco grava um valor
/// aleatório, de uso único, preso ao usuário que pediu o link.

export const connectRefreshSkewMs = 120_000;

export function connectRedirectUri(input: {
  partner: string;
  admin: string;
  surface: string;
}): string {
  const partner = input.partner.trim();
  const admin = input.admin.trim();
  const chosen = input.surface === "admin" && admin.startsWith("https://")
    ? admin
    : partner;
  if (!chosen.startsWith("https://")) throw new Error("pagbank_connect");
  return chosen;
}

export type ConnectSession = {
  venueId: string;
  redirectUri: string;
};

export async function completePagbankConnect(input: {
  userId: string;
  code: string;
  state: string;
  consume: (state: string, userId: string) => Promise<ConnectSession | null>;
  exchange: (
    code: string,
    redirectUri: string,
  ) => Promise<{
    accessToken: string;
    refreshToken: string;
    expiresIn: number;
    accountId: string;
  }>;
  /// Grava conta e token numa transação só. Recusa com
  /// PagbankAccountConflict se a casa já tem outra conta PagBank.
  link: (
    venueId: string,
    accountId: string,
    tokens: {
      accessToken: string;
      refreshToken: string;
      expiresAt: string | null;
    },
  ) => Promise<void>;
  nowMs?: number;
}): Promise<{ venueId: string }> {
  const session = await input.consume(input.state, input.userId);
  if (!session?.venueId || !session.redirectUri.startsWith("https://")) {
    throw new Error("state");
  }
  const exchanged = await input.exchange(input.code, session.redirectUri);
  const now = input.nowMs ?? Date.now();
  await input.link(session.venueId, exchanged.accountId, {
    accessToken: exchanged.accessToken,
    refreshToken: exchanged.refreshToken,
    expiresAt: exchanged.expiresIn > 0
      ? new Date(now + exchanged.expiresIn * 1000).toISOString()
      : null,
  });
  return { venueId: session.venueId };
}

/// Renova antes do vencimento. Sem data, espera o 401.
export async function freshConnectAccess(input: {
  accessToken: string;
  refreshToken: string;
  expiresAtMs: number | null;
  nowMs: number;
  refresh: () => Promise<{
    accessToken: string;
    refreshToken: string;
    expiresIn: number;
  }>;
}): Promise<{
  accessToken: string;
  refreshToken: string;
  expiresAtMs: number | null;
  refreshed: boolean;
}> {
  const due = input.expiresAtMs != null &&
    input.expiresAtMs - input.nowMs <= connectRefreshSkewMs;
  if (!due || !input.refreshToken) {
    return {
      accessToken: input.accessToken,
      refreshToken: input.refreshToken,
      expiresAtMs: input.expiresAtMs,
      refreshed: false,
    };
  }
  const next = await input.refresh();
  return {
    accessToken: next.accessToken,
    refreshToken: next.refreshToken || input.refreshToken,
    expiresAtMs: next.expiresIn > 0
      ? input.nowMs + next.expiresIn * 1000
      : null,
    refreshed: true,
  };
}
