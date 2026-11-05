const cardField =
  /"(number|ccv|cvv|expiryMonth|expiryYear)"\s*:\s*"(?:\\.|[^"\\])*"/gi;

/// 13 a 19 dígitos, com espaço ou hífen opcional entre eles.
const pan = /\b(?:\d[ -]?){12,18}\d\b/g;

const expiry = /\b(?:0[1-9]|1[0-2])\s*[/-]\s*(?:20\d{2}|\d{2})\b/g;

const secretKeys = new Set([
  "number",
  "ccv",
  "cvv",
  "expiryMonth",
  "expiryYear",
]);

/// Tira número, CVV e validade de texto que possa ir para log, erro ou resposta.
export function redactSensitive(
  text: string,
  secrets: readonly string[] = [],
): string {
  let out = text.replace(cardField, (_match, key: string) => {
    return `"${key}":"[redacted]"`;
  });
  out = out.replace(pan, "[redacted]");
  out = out.replace(expiry, "[redacted]");
  for (const secret of secrets) {
    out = maskSecret(out, secret);
  }
  return out;
}

export function sensitiveStrings(payload: unknown): string[] {
  const found: string[] = [];
  walk(payload, found);
  return found;
}

function walk(value: unknown, found: string[]): void {
  if (Array.isArray(value)) {
    for (const item of value) walk(item, found);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, inner] of Object.entries(value)) {
    if (secretKeys.has(key) && typeof inner === "string" && inner.length > 0) {
      found.push(inner);
    } else {
      walk(inner, found);
    }
  }
}

function maskSecret(text: string, secret: string): string {
  const trimmed = secret.trim();
  if (trimmed.length < 2) return text;
  if (trimmed.length < 3 && !/^\d{2}$/.test(trimmed)) return text;
  const escaped = trimmed.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return text.replace(new RegExp(escaped, "g"), "[redacted]");
}
