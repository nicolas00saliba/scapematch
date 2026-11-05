import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { clientIp } from "../_shared/client_ip.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import {
  cardBrand,
  last4Digits,
  storeSavedCard,
} from "../_shared/saved_card.ts";
import { readCard, tokenizePublicResponse } from "../_shared/tokenize_input.ts";
import {
  gateTokenize,
  tokenizeLimitedMessage,
} from "../_shared/tokenize_limit.ts";

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

    const card = readCard(await req.json());
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
          remoteIp: clientIp(req) ?? undefined,
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
        const last4 = last4Digits(tokenized.creditCardNumber);
        const brand = cardBrand(tokenized.creditCardBrand);
        const savedCardId = await storeSavedCard(admin, {
          userId: user.id,
          customerId,
          token: tokenized.creditCardToken,
          last4,
          brand,
        });
        responseBody = tokenizePublicResponse({
          id: savedCardId,
          last4,
          brand,
        });
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
