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

/// Dados do titular em creditCardHolderInfo. A chave tem de ser o campo inteiro.
const holderKey =
  "name|email|phone|mobile[_-]?phone|postal[_-]?code|address[_-]?number|address[_-]?complement";

const namedHolderField = new RegExp(
  `"(${holderKey})"\\s*:\\s*"(?:\\\\.|[^"\\\\])*"`,
  "gi",
);

const labeledHolder = new RegExp(
  `\\b(${holderKey})\\b(\\s*[:=]\\s*)(?:"((?:\\\\.|[^"\\\\])*)"|(\\S+))`,
  "gi",
);

/// Mascara PAN e, só em campos nomeados, CVV, validade, token do cartão,
/// documento e os dados do titular (`creditCardHolderInfo`).
/// Cobre camelCase e snake_case. Não troca um "12" solto nem a palavra solta.
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
    .replace(labeledDocument, (_match, key: string, sep: string) => `${key}${sep}[redacted]`)
    .replace(namedHolderField, (_match, key: string) => `"${key}":"[redacted]"`)
    .replace(
      labeledHolder,
      (_match, key: string, sep: string, quoted?: string) =>
        quoted === undefined
          ? `${key}${sep}[redacted]`
          : `${key}${sep}"[redacted]"`,
    );
}
