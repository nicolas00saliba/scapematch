/// Revoga no PagBank os tokens que o EscapeMatch deixa de usar: os da conta
/// desconectada e os de uma conexão recusada (segunda conta, outra casa).
/// Melhor esforço: nunca lança, nunca devolve nem registra token. O fluxo
/// principal (desconectar, recusar com 409) não depende disto.

export type RevokeCall = (input: {
  bearerToken: string;
  token: string;
  hint: "access_token" | "refresh_token";
}) => Promise<void>;

export type RevokeResult = {
  attempted: number;
  revoked: number;
  failed: number;
};

export async function revokeConnectTokens(
  revoke: RevokeCall,
  tokens: { accessToken?: string | null; refreshToken?: string | null },
): Promise<RevokeResult> {
  const access = (tokens.accessToken ?? "").trim();
  const refresh = (tokens.refreshToken ?? "").trim();
  const result: RevokeResult = { attempted: 0, revoked: 0, failed: 0 };
  // O refresh vai primeiro: o access ainda vale como Authorization. Depois
  // o próprio access.
  const queue: Parameters<RevokeCall>[0][] = [];
  if (refresh && access) {
    queue.push({ bearerToken: access, token: refresh, hint: "refresh_token" });
  }
  if (access) {
    queue.push({ bearerToken: access, token: access, hint: "access_token" });
  }
  for (const item of queue) {
    result.attempted += 1;
    try {
      await revoke(item);
      result.revoked += 1;
    } catch (_error) {
      result.failed += 1;
    }
  }
  return result;
}
