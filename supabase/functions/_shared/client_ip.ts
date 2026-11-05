/// IP de quem chamou a função, lido só dos headers que a borda coloca.
/// O body não entra: um remote_ip enviado pelo cliente é ignorado.
export function clientIp(req: Request): string {
  const forwarded = firstAddress(req.headers.get("x-forwarded-for"));
  if (forwarded) return forwarded;
  const cloudflare = firstAddress(req.headers.get("cf-connecting-ip"));
  if (cloudflare) return cloudflare;
  const real = firstAddress(req.headers.get("x-real-ip"));
  if (real) return real;
  return "127.0.0.1";
}

function firstAddress(header: string | null): string {
  const value = header?.split(",")[0]?.trim() ?? "";
  if (!value || value.length > 64) return "";
  if (!/^[0-9a-fA-F:.]+$/.test(value)) return "";
  return value;
}
