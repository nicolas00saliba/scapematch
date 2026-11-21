import { handleMpPublicKey } from "../_shared/mp_public_key.ts";

if (import.meta.main) {
  Deno.serve((req) => handleMpPublicKey(req, Deno.env));
}
