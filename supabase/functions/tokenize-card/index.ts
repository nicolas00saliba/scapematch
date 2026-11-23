import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { hasRawCardData } from "../_shared/raw_card.ts";

/// O número do cartão não passa pelo servidor. O token nasce no aparelho,
/// no Mercado Pago, e a cobrança recebe só `card_token`.
Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const body = await req.json().catch(() => ({}));
  if (hasRawCardData(body)) {
    return json({ error: "O número do cartão não passa pelo servidor." }, 400);
  }
  return json({ error: "token_no_aparelho" }, 400);
});
