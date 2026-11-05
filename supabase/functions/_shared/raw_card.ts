const rawCardKey =
  /^(number|ccv|cvv|cvc|expiry|expiryMonth|expiryYear|expiry_month|expiry_year)$/i;

/// Verdadeiro quando o JSON traz número, CVV ou validade, em qualquer nível.
export function hasRawCardData(value: unknown, depth = 0): boolean {
  if (depth > 8 || value == null || typeof value !== "object") return false;
  if (Array.isArray(value)) {
    return value.some((item) => hasRawCardData(item, depth + 1));
  }
  for (const [key, nested] of Object.entries(value)) {
    if (rawCardKey.test(key)) return true;
    if (hasRawCardData(nested, depth + 1)) return true;
  }
  return false;
}
