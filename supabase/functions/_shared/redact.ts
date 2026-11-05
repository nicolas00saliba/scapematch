const namedCardField =
  /"(number|ccv|cvv|expiryMonth|expiryYear)"\s*:\s*"(?:\\.|[^"\\])*"/gi;

/// 13 a 19 dígitos, com espaço ou hífen opcional entre eles.
const pan = /\b(?:\d[ -]?){12,18}\d\b/g;

/// Mascara PAN e, só em campos nomeados, CVV e validade.
/// Não troca um "12" solto nem outros números curtos.
export function redactSensitive(text: string): string {
  return text
    .replace(namedCardField, (_match, key: string) => `"${key}":"[redacted]"`)
    .replace(pan, "[redacted]");
}
