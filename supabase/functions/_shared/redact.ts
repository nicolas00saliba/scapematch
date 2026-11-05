const namedCardField =
  /"(number|ccv|cvv|expiryMonth|expiryYear|credit[_-]?card[_-]?token)"\s*:\s*"(?:\\.|[^"\\])*"/gi;

/// Token fora do par `"chave":"valor"`, como numa descrição de erro.
const namedTokenInText =
  /\b(credit[_-]?card[_-]?token)\b(\s*[:=]\s*)(?:"((?:\\.|[^"\\])*)"|([A-Za-z0-9_-]{8,}))/gi;

/// 13 a 19 dígitos, com espaço ou hífen opcional entre eles.
const pan = /\b(?:\d[ -]?){12,18}\d\b/g;

/// CPF ou CNPJ só quando o campo tem nome. Um número solto não entra aqui.
const namedDocumentField =
  /"(cpfCnpj|cpf_cnpj|cpf)"\s*:\s*"(?:\\.|[^"\\])*"/gi;

const labeledDocument =
  /\b(cpfCnpj|cpf_cnpj|cpf)\b(\s*[:=]\s*)(?:"[\d.\-\/]+"|[\d.\-\/]{11,18})/gi;

/// Mascara PAN e, só em campos nomeados, CVV, validade e token do cartão.
/// Cobre camelCase e snake_case (`creditCardToken`, `credit_card_token`).
/// Não troca um "12" solto nem outros números curtos.
export function redactSensitive(text: string): string {
  return text
    .replace(namedCardField, (_match, key: string) => `"${key}":"[redacted]"`)
    .replace(
      namedTokenInText,
      (_match, key: string, sep: string, quoted?: string) =>
        quoted === undefined
          ? `${key}${sep}[redacted]`
          : `${key}${sep}"[redacted]"`,
    )
    .replace(pan, "[redacted]")
    .replace(namedDocumentField, (_match, key: string) => `"${key}":"[redacted]"`)
    .replace(labeledDocument, (_match, key: string, sep: string) => `${key}${sep}[redacted]`);
}
