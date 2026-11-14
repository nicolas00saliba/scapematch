// Consulta e, quando não há link, envia documentos da subconta.
// A apiKey fica no servidor. Este arquivo não publica a função.

import { handleVenueDocuments, roleOf } from "../_shared/venue_documents.ts";
import { readJwtClaims, recentStrongAuth } from "../_shared/venue_payouts.ts";
import { payoutStore } from "../_shared/venue_payout_store.ts";

if (import.meta.main) {
  const store = payoutStore(Deno.env);
  Deno.serve((req) =>
    handleVenueDocuments(req, {
      env: Deno.env,
      fetchFn: fetch,
      actor: (jwt) => store.actor(jwt),
      role: (venueId, userId, jwt) => roleOf(store, venueId, userId, jwt),
      subaccount: async (venueId) => {
        const apiKey = await store.rpc("read_venue_asaas_key", {
          p_venue_id: venueId,
        });
        const walletId = await store.rpc("venue_payout_wallet", {
          p_venue_id: venueId,
        });
        return {
          apiKey: typeof apiKey === "string" ? apiKey : "",
          walletId: typeof walletId === "string" ? walletId : "",
        };
      },
      strongAuth: async (jwt) => {
        const actor = await store.actor(jwt);
        if (!actor) return false;
        const totp = await store.verifiedTotp(actor.id);
        return recentStrongAuth(
          readJwtClaims(jwt),
          totp,
          Math.floor(Date.now() / 1000),
        ) === "ok";
      },
    })
  );
}
