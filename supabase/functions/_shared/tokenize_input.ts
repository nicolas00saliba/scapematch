import { savedCardView } from "./saved_card.ts";

export type CardInput = {
  holderName: string;
  number: string;
  expiryMonth: string;
  expiryYear: string;
  ccv: string;
  holderCpfCnpj: string;
  holderPostalCode: string;
  holderAddressNumber: string;
  holderPhone: string;
};

function text(body: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = body[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

/// Lê o cartão do body. Nulo quando falta número, CVV, validade ou nome.
/// O motivo não inclui o valor digitado.
export function readCard(body: unknown): CardInput | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const record = body as Record<string, unknown>;
  const card = text(record, ["holderName", "holder_name"]).length > 0 &&
      text(record, ["number"]).length > 0 &&
      text(record, ["ccv", "cvv"]).length > 0 &&
      text(record, ["expiryMonth", "expiry_month"]).length > 0 &&
      text(record, ["expiryYear", "expiry_year"]).length > 0
    ? {
      holderName: text(record, ["holderName", "holder_name"]),
      number: text(record, ["number"]),
      expiryMonth: text(record, ["expiryMonth", "expiry_month"]),
      expiryYear: text(record, ["expiryYear", "expiry_year"]),
      ccv: text(record, ["ccv", "cvv"]),
      holderCpfCnpj: text(record, ["holderCpfCnpj", "holder_cpf_cnpj"]),
      holderPostalCode: text(record, [
        "holderPostalCode",
        "holder_postal_code",
      ]),
      holderAddressNumber:
        text(record, ["holderAddressNumber", "holder_address_number"]) ||
        "S/N",
      holderPhone: text(record, ["holderPhone", "holder_phone"]),
    }
    : null;
  return card;
}

/// Resposta da tokenização. Só o id interno, os 4 dígitos e a bandeira.
export function tokenizePublicResponse(card: {
  id: string;
  last4: string;
  brand: string;
  creditCardToken?: string;
}): { saved_card_id: string; last4: string; brand: string } {
  const view = savedCardView(card);
  return {
    saved_card_id: view.saved_card_id,
    last4: view.card_last4,
    brand: view.card_brand,
  };
}
