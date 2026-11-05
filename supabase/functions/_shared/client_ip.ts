/// IP de quem chamou a função, lido só dos headers que a borda coloca.
/// O gateway do Supabase sobrescreve `x-real-ip` e anexa o IP real ao fim
/// de `x-forwarded-for`. O primeiro endereço dessa lista pode ser do cliente.
/// O body não entra. Sem header válido, devolve nulo: o pedido não leva remoteIp.
export function clientIp(req: Request): string | null {
  const real = singleAddress(req.headers.get("x-real-ip"));
  if (real) return real;
  const cloudflare = singleAddress(req.headers.get("cf-connecting-ip"));
  if (cloudflare) return cloudflare;
  return lastForwarded(req.headers.get("x-forwarded-for"));
}

function singleAddress(header: string | null): string | null {
  const value = unbracket(header?.trim() ?? "");
  if (!value || value.length > 64) return null;
  return isIp(value) ? value : null;
}

function lastForwarded(header: string | null): string | null {
  if (!header) return null;
  const parts = header.split(",").map((part) => unbracket(part.trim())).filter(
    (part) => part.length > 0,
  );
  const last = parts.at(-1) ?? "";
  if (!last || last.length > 64 || !isIp(last)) return null;
  return last;
}

function unbracket(value: string): string {
  if (value.startsWith("[") && value.endsWith("]") && value.length > 2) {
    return value.slice(1, -1);
  }
  return value;
}

function isIp(value: string): boolean {
  return isIpv4(value) || isIpv6(value);
}

function isIpv4(value: string): boolean {
  const parts = value.split(".");
  if (parts.length !== 4) return false;
  return parts.every((part) => {
    if (!/^\d{1,3}$/.test(part)) return false;
    if (part.length > 1 && part.startsWith("0")) return false;
    const number = Number(part);
    return number >= 0 && number <= 255;
  });
}

function isIpv6(value: string): boolean {
  if (value.length === 0 || value.length > 45 || value.includes("%")) {
    return false;
  }
  const halves = value.split("::");
  if (halves.length > 2) return false;
  const left = ipv6Groups(halves[0]);
  if (left === null) return false;
  if (halves.length === 1) return left === 8;
  const right = ipv6Groups(halves[1]);
  if (right === null) return false;
  return left + right <= 7;
}

function ipv6Groups(side: string): number | null {
  if (side === "") return 0;
  const parts = side.split(":");
  let count = 0;
  for (let index = 0; index < parts.length; index++) {
    const part = parts[index];
    if (part.includes(".")) {
      if (index !== parts.length - 1 || !isIpv4(part)) return null;
      count += 2;
      continue;
    }
    if (!/^[0-9a-fA-F]{1,4}$/.test(part)) return null;
    count += 1;
  }
  return count;
}
