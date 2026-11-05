import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type CardStore,
  type SavedCard,
  cardBrand,
  cardForCharge,
  last4Digits,
  requestedSavedCardId,
  savedCardView,
} from "./saved_card.ts";

const cardA: SavedCard = {
  id: "11111111-1111-1111-1111-111111111111",
  userId: "user-a",
  asaasCustomerId: "cus_a",
  creditCardToken: "tok_user_a_secret",
  last4: "1111",
  brand: "VISA",
};

const cardB: SavedCard = {
  id: "22222222-2222-2222-2222-222222222222",
  userId: "user-b",
  asaasCustomerId: "cus_b",
  creditCardToken: "tok_user_b_secret",
  last4: "2222",
  brand: "MASTERCARD",
};

function storeOf(cards: readonly SavedCard[]): CardStore {
  return {
    findOwned(userId, customerId, cardId) {
      const found = cards.find((card) =>
        card.id === cardId &&
        card.userId === userId &&
        card.asaasCustomerId === customerId
      );
      return Promise.resolve(found ?? null);
    },
  };
}

Deno.test("usuário B não cobra com o cartão salvo do A", async () => {
  const store = storeOf([cardA, cardB]);
  const own = await cardForCharge(store, "user-a", "cus_a", cardA.id);
  assertEquals(own.creditCardToken, cardA.creditCardToken);

  let message = "";
  try {
    await cardForCharge(store, "user-b", "cus_b", cardA.id);
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  assert(message.length > 0);
  assertEquals(message.includes(cardA.creditCardToken), false);
  assertEquals(message.includes(cardA.last4), false);

  const leaky: CardStore = {
    findOwned: () => Promise.resolve(cardA),
  };
  let leaked = "";
  try {
    await cardForCharge(leaky, "user-b", "cus_b", cardA.id);
  } catch (error) {
    leaked = error instanceof Error ? error.message : String(error);
  }
  assertEquals(leaked, "cartão não encontrado");
  assertEquals(leaked.includes(cardA.creditCardToken), false);
});

Deno.test("o token do cliente e o token salvo não voltam na resposta", () => {
  const requested = requestedSavedCardId({
    saved_card_id: cardB.id,
    credit_card_token: cardA.creditCardToken,
  });
  assertEquals(requested, cardB.id);
  assertEquals(JSON.stringify({ saved_card_id: requested }).includes(cardA.creditCardToken), false);

  const view = savedCardView(cardA);
  const encoded = JSON.stringify(view);
  assertEquals(encoded.includes(cardA.creditCardToken), false);
  assertEquals(view.card_last4, "1111");
  assertEquals(view.card_brand, "VISA");
  assertEquals(Object.keys(view).includes("creditCardToken"), false);
  assertEquals(Object.keys(view).includes("credit_card_token"), false);
});

Deno.test("o final do cartão guarda só 4 dígitos", () => {
  assertEquals(last4Digits("8829"), "8829");
  assertEquals(last4Digits("4111111111111111"), "1111");
  assertEquals(cardBrand("VISA"), "VISA");
  assertEquals(cardBrand("4111111111111111"), "");
});
