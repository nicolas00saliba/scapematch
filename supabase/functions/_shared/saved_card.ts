export type SavedCard = {
  id: string;
  userId: string;
  asaasCustomerId: string;
  creditCardToken: string;
  last4: string;
  brand: string;
};

export type SavedCardView = {
  saved_card_id: string;
  card_last4: string;
  card_brand: string;
};

export type CardStore = {
  findOwned(
    userId: string,
    customerId: string,
    cardId: string,
  ): Promise<SavedCard | null>;
};

/// O body pode até trazer credit_card_token. A cobrança não lê esse campo.
export function requestedSavedCardId(body: {
  saved_card_id?: string;
  credit_card_token?: string;
}): string {
  return (body.saved_card_id ?? "").trim();
}

export function last4Digits(value: string): string {
  const digits = value.replace(/\D/g, "");
  if (digits.length < 4) {
    throw new Error("Resposta do Asaas sem final do cartão");
  }
  return digits.slice(-4);
}

export function cardBrand(value: string): string {
  const brand = value.trim();
  if (!/^[A-Za-z0-9 _-]{1,32}$/.test(brand)) return "";
  if ((brand.match(/\d/g) ?? []).length >= 6) return "";
  return brand;
}

export function savedCardView(card: {
  id: string;
  last4: string;
  brand: string;
  creditCardToken?: string;
}): SavedCardView {
  return {
    saved_card_id: card.id,
    card_last4: card.last4,
    card_brand: card.brand,
  };
}

export function assertOwnedCard(
  card: SavedCard | null,
  userId: string,
  customerId: string,
  cardId: string,
): SavedCard {
  if (
    !card ||
    card.id !== cardId ||
    card.userId !== userId ||
    card.asaasCustomerId !== customerId ||
    card.creditCardToken.length < 8
  ) {
    throw new Error("cartão não encontrado");
  }
  return card;
}

export async function cardForCharge(
  store: CardStore,
  userId: string,
  customerId: string,
  cardId: string,
): Promise<SavedCard> {
  const row = await store.findOwned(userId, customerId, cardId);
  return assertOwnedCard(row, userId, customerId, cardId);
}
