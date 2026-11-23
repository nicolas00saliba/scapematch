/// Tipos de empresa da API de subcontas do PagBank. Só pessoa jurídica.
/// Pessoa física não envia `companyType`.
export const companyTypes = [
  "MEI",
  "LIMITED",
  "INDIVIDUAL",
  "ASSOCIATION",
] as const;

export type PagBankCompanyType = (typeof companyTypes)[number];

const companyTypeSet = new Set<string>(companyTypes);

/// CNPJ sem tipo conhecido continua LIMITED, o valor que a provisão já usava.
/// CPF devolve `undefined` para o JSON omitir a chave.
export function companyTypeForSubaccount(
  documentKind: string,
  companyType: string | null | undefined,
): PagBankCompanyType | undefined {
  if (documentKind !== "cnpj") return undefined;
  const value = (companyType ?? "").trim().toUpperCase();
  if (companyTypeSet.has(value)) return value as PagBankCompanyType;
  return "LIMITED";
}
