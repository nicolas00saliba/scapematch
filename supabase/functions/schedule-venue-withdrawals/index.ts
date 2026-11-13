import { payoutStore } from "../_shared/venue_payout_store.ts";
import { createSecretCache } from "../_shared/cron_secret.ts";
import {
  handleScheduledWithdrawals,
  payoutProvider,
  transferClient,
} from "../_shared/venue_payouts.ts";

const secretCache = createSecretCache();

if (import.meta.main) {
  Deno.serve((req) =>
    handleScheduledWithdrawals(req, {
      env: Deno.env,
      store: payoutStore(Deno.env),
      clientFor: (apiKey) => transferClient(payoutProvider(Deno.env, apiKey)),
      secretCache,
    })
  );
}
