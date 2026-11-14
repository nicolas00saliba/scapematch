// Consulta e, quando não há link, envia documentos da subconta.
// A apiKey fica no servidor. Este arquivo não publica a função.

import {
  handleVenueDocuments,
  type DocumentAccess,
} from "../_shared/venue_documents.ts";
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

async function roleOf(
  store: ReturnType<typeof payoutStore>,
  venueId: string,
  userId: string,
  jwt: string,
): Promise<DocumentAccess> {
  try {
    const data = await store.rpc("venue_payout_snapshot", {
      p_venue_id: venueId,
      p_actor: userId,
      p_as_admin: false,
    });
    const role = record(data)?.role;
    if (role === "owner" || role === "partner") return role;
  } catch {
    // Dono ausente cai no admin abaixo.
  }
  // Igual ao venue-payouts: admin só entra com sessão aal2 (MFA).
  if (readJwtClaims(jwt).aal !== "aal2") return "none";
  if (await store.isAdmin(userId)) return "admin";
  return "none";
}

function record(value: unknown): { role?: string } | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as { role?: string };
}
