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

/// O texto é estável. A cobrança não lê `error.message` no próprio arquivo.
export function isMissingCard(error: unknown): boolean {
  return error instanceof Error && error.message === "cartão não encontrado";
}

export type CardRpc = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
};

/// Grava o token já cifrado. O retorno é só o id interno.
export async function storeSavedCard(
  db: CardRpc,
  input: {
    userId: string;
    customerId: string;
    token: string;
    last4: string;
    brand: string;
    holderMatches?: boolean;
    holderDocumentHash?: string | null;
    cardKey?: string | null;
  },
): Promise<string> {
  const { data, error } = await db.rpc("insert_saved_card", {
    p_user_id: input.userId,
    p_customer_id: input.customerId,
    p_token: input.token,
    p_last4: input.last4,
    p_brand: input.brand,
  });
  if (error || typeof data !== "string" || data.length < 8) {
    throw new Error("Não foi possível guardar o cartão.");
  }
  if (typeof input.holderMatches === "boolean") {
    const marked = await db.rpc("mark_saved_card_holder_match", {
      p_card_id: data,
      p_user_id: input.userId,
      p_matches: input.holderMatches,
    });
    if (marked.error) throw new Error("Não foi possível guardar o cartão.");
  }
  if (input.holderDocumentHash || input.cardKey) {
    const keyed = await db.rpc("mark_saved_card_payer_key", {
      p_card_id: data,
      p_user_id: input.userId,
      p_document_hash: input.holderDocumentHash ?? null,
      p_card_key: input.cardKey ?? null,
    });
    if (keyed.error) throw new Error("Não foi possível guardar o cartão.");
  }
  return data;
}

/// Lê o token cifrado do cartão deste jogador. Outro user_id não devolve linha.
export async function loadOwnedCard(
  db: CardRpc,
  userId: string,
  customerId: string,
  cardId: string,
): Promise<SavedCard | null> {
  const { data, error } = await db.rpc("load_owned_card", {
    p_user_id: userId,
    p_customer_id: customerId,
    p_card_id: cardId,
  });
  if (error) throw new Error("cartão não encontrado");
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") return null;
  const record = row as Record<string, unknown>;
  const id = typeof record.id === "string" ? record.id : "";
  const token = typeof record.token === "string" ? record.token : "";
  const last4 = typeof record.last4 === "string" ? record.last4 : "";
  const brand = typeof record.brand === "string" ? record.brand : "";
  if (!id || token.length < 8) return null;
  return {
    id,
    userId,
    asaasCustomerId: customerId,
    creditCardToken: token,
    last4,
    brand,
  };
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
