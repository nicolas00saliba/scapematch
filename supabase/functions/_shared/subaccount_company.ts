/// Tipos de empresa da API de subcontas do Asaas. Só pessoa jurídica.
/// Pessoa física não envia `companyType`.
export const asaasCompanyTypes = [
  "MEI",
  "LIMITED",
  "INDIVIDUAL",
  "ASSOCIATION",
] as const;

export type AsaasCompanyType = (typeof asaasCompanyTypes)[number];

const companyTypeSet = new Set<string>(asaasCompanyTypes);

/// CNPJ sem tipo conhecido continua LIMITED, o valor que a provisão já usava.
/// CPF devolve `undefined` para o JSON omitir a chave.
export function companyTypeForSubaccount(
  documentKind: string,
  companyType: string | null | undefined,
): AsaasCompanyType | undefined {
  if (documentKind !== "cnpj") return undefined;
  const value = (companyType ?? "").trim().toUpperCase();
  if (companyTypeSet.has(value)) return value as AsaasCompanyType;
  return "LIMITED";
}
