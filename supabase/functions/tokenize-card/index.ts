import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import {
  assertOwnedCard,
  cardBrand,
  last4Digits,
  type SavedCard,
} from "../_shared/saved_card.ts";
import { readCard, tokenizePublicResponse } from "../_shared/tokenize_input.ts";
import {
  gateTokenize,
  tokenizeLimitedMessage,
} from "../_shared/tokenize_limit.ts";

type SavedCardRow = {
  id: string;
  user_id: string;
  asaas_customer_id: string;
  credit_card_token: string;
  last4: string;
  brand: string;
};

type ChargeDb = {
  from(...args: unknown[]): any;
};

const genericFailure = "Não foi possível guardar o cartão.";

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    const user = userData.user;
    if (userError || !user) return json({ error: "not authenticated" }, 401);

    const remoteIp =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      "127.0.0.1";
    const card = readCard(await req.json(), remoteIp);
    if (!card) return json({ error: "Dados do cartão incompletos." }, 400);

    const admin = createClient(url, service);
    let responseBody: ReturnType<typeof tokenizePublicResponse> | null = null;
    const decision = await gateTokenize(
      async () => {
        const claim = await admin.rpc("claim_card_tokenize_attempt", {
          p_user_id: user.id,
        });
        if (claim.error) throw new Error(genericFailure);
        return claim.data === true;
      },
      async () => {
        const { data: profile } = await admin
          .from("profiles")
          .select("display_name, asaas_customer_id")
          .eq("id", user.id)
          .maybeSingle();
        const asaas = AsaasProvider.fromEnv(Deno.env);
        let customerId = profile?.asaas_customer_id as string | null;
        if (!customerId) {
          const created = await asaas.createCustomer({
            name: profile?.display_name ?? "Jogador",
            email: user.email ?? "",
            externalReference: user.id,
          });
          customerId = created.id;
          await admin.from("profiles").update({
            asaas_customer_id: customerId,
          }).eq(
            "id",
            user.id,
          );
        }

        const tokenized = await asaas.tokenizeCard({
          customer: customerId,
          remoteIp: card.remoteIp,
          creditCard: {
            holderName: card.holderName,
            number: card.number,
            expiryMonth: card.expiryMonth,
            expiryYear: card.expiryYear,
            ccv: card.ccv,
          },
          creditCardHolderInfo: {
            name: card.holderName,
            email: user.email ?? "",
            cpfCnpj: card.holderCpfCnpj,
            postalCode: card.holderPostalCode,
            addressNumber: card.holderAddressNumber,
            phone: card.holderPhone,
          },
        });
        const inserted = await admin
          .from("saved_cards")
          .insert({
            user_id: user.id,
            asaas_customer_id: customerId,
            credit_card_token: tokenized.creditCardToken,
            last4: last4Digits(tokenized.creditCardNumber),
            brand: cardBrand(tokenized.creditCardBrand),
          })
          .select(
            "id, user_id, asaas_customer_id, credit_card_token, last4, brand",
          )
          .single();
        if (inserted.error || !inserted.data) {
          throw new Error(genericFailure);
        }
        const owned = assertOwnedCard(
          toSavedCard(inserted.data as SavedCardRow),
          user.id,
          customerId,
          inserted.data.id as string,
        );
        responseBody = tokenizePublicResponse(owned);
      },
    );
    if (decision === "limited" || !responseBody) {
      return json({ error: tokenizeLimitedMessage }, 429);
    }
    return json(responseBody);
  } catch {
    return json({ error: genericFailure }, 400);
  }
});

function toSavedCard(row: SavedCardRow): SavedCard {
  return {
    id: row.id,
    userId: row.user_id,
    asaasCustomerId: row.asaas_customer_id,
    creditCardToken: row.credit_card_token,
    last4: row.last4,
    brand: row.brand,
  };
}
