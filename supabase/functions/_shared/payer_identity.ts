/// SHA-256 dos dígitos. O mesmo cálculo de private.document_hash.
export async function documentHash(raw: string | null | undefined): Promise<string | null> {
  const digits = (raw ?? "").replace(/\D/g, "");
  if (!/^\d{11}$/.test(digits) && !/^\d{14}$/.test(digits)) return null;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(digits),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/// O Asaas não devolve fingerprint. O token pertence a um cliente.
/// A chave entre contas é bandeira + 4 finais.
export function cardKey(
  brand: string | null | undefined,
  last4: string | null | undefined,
): string | null {
  const tail = (last4 ?? "").replace(/\D/g, "");
  if (!/^\d{4}$/.test(tail)) return null;
  const clean = (brand ?? "").replace(/[^A-Za-z0-9]/g, "").toLowerCase();
  if (!clean) return null;
  return `${clean}:${tail}`;
}
