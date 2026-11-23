import { payoutStore } from "../_shared/venue_payout_store.ts";
import { handleVenuePayouts } from "../_shared/venue_payouts.ts";

if (import.meta.main) {
  Deno.serve((req) =>
    handleVenuePayouts(req, {
      env: Deno.env,
      store: payoutStore(Deno.env),
    })
  );
}
