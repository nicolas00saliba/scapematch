import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import {
  playerCpfDigits,
  resolveCustomerWithCpf,
  storeReplacedCustomer,
} from "../_shared/player_cpf.ts";
import { clientIp } from "../_shared/client_ip.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { cardKey, documentHash } from "../_shared/payer_identity.ts";
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
    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, asaas_customer_id, cpf")
      .eq("id", user.id)
      .maybeSingle();
    const cpf = playerCpfDigits(profile?.cpf);
    if (!cpf) return json({ error: "cpf_required" }, 422);
    const holderCpf = playerCpfDigits(card.holderCpfCnpj);
    if (!holderCpf) return json({ error: "holder_cpf_invalid" }, 400);
    const holderMatches = holderCpf === cpf;
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
        const asaas = AsaasProvider.fromEnv(Deno.env);
        const previousCustomer = profile?.asaas_customer_id as string | null;
        const resolvedCustomer = await resolveCustomerWithCpf(asaas, {
          customerId: previousCustomer,
          name: profile?.display_name ?? "Jogador",
          email: user.email ?? "",
          externalReference: user.id,
          cpf,
        });
        const storedCustomer = await storeReplacedCustomer(
          admin,
          user.id,
          previousCustomer,
          resolvedCustomer.id,
          asaas,
        );
        const customerId = storedCustomer.id;

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
            cpfCnpj: holderCpf,
            postalCode: card.holderPostalCode,
            addressNumber: card.holderAddressNumber,
            phone: card.holderPhone,
          },
        });
        const last4 = last4Digits(tokenized.creditCardNumber);
        const brand = cardBrand(tokenized.creditCardBrand);
        const payerHash = await documentHash(holderCpf);
        const payerCardKey = cardKey(brand, last4);
        const savedCardId = await storeSavedCard(admin, {
          userId: user.id,
          customerId,
          token: tokenized.creditCardToken,
          last4,
          brand,
          holderMatches,
          holderDocumentHash: payerHash,
          cardKey: payerCardKey,
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
  } catch (error) {
    const failure = clientFailure(error, "tokenize-card");
    return json(failure.body, failure.status);
  }
});
