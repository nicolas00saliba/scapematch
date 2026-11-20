// Admin nas Edge Functions só vale com sessão aal2 (MFA), igual ao banco
// (private.is_admin_aal2) e ao venue-documents/venue-payouts.
// O gateway (verify_jwt) e o auth.getUser() já conferem a assinatura do JWT.
// Aqui só lemos a claim `aal` do mesmo token.

export function bearerToken(authHeader: string): string {
  return authHeader.replace(/^Bearer\s+/i, "").trim();
}

export function sessionAal(authHeader: string): string {
  const part = bearerToken(authHeader).split(".")[1] ?? "";
  if (!part) return "";
  try {
    const padded = part.replace(/-/g, "+").replace(/_/g, "/") +
      "=".repeat((4 - (part.length % 4)) % 4);
    const claims = JSON.parse(atob(padded)) as Record<string, unknown>;
    return typeof claims.aal === "string" ? claims.aal : "";
  } catch {
    return "";
  }
}

/// Linha em `admins` só conta como admin quando a sessão é aal2.
export function adminWithMfa(isAdminRow: boolean, authHeader: string): boolean {
  return isAdminRow && sessionAal(authHeader) === "aal2";
}
