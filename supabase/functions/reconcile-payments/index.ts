import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { logCaught } from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import {
  reconcileAsaasTimeoutMs,
  reconcilePayments,
} from "../_shared/reconcile_payments.ts";
import { settleAuthorizedCards, settleGroup } from "../_shared/settle_group.ts";

type Deps = {
  // deno-lint-ignore no-explicit-any
  admin?: any;
  asaas?: AsaasProvider;
  reconcileSecret?: string;
};

export async function handleReconcile(
  req: Request,
  deps?: Deps,
): Promise<Response> {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  const secret = deps?.reconcileSecret ?? Deno.env.get("RECONCILE_SECRET") ??
    "";
  const header = req.headers.get("x-reconcile-secret") ?? "";
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  try {
    const admin = deps?.admin ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const asaas = deps?.asaas ??
      AsaasProvider.fromEnv(Deno.env, reconcileAsaasTimeoutMs);
    const groupId = await settleGroupId(req);
    const reconciled = await reconcilePayments(admin, asaas);
    if (groupId) {
      try {
        await settleGroup(admin, asaas, groupId);
      } catch (error) {
        logCaught("settle-charges", error);
      }
    }
    await settleAuthorizedCards(admin, asaas);
    return json(reconciled);
  } catch (_error) {
    return json({ error: "erro" }, 500);
  }
}

const groupIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function settleGroupId(req: Request): Promise<string> {
  try {
    const body = await req.clone().json();
    const id = body && typeof body === "object"
      ? (body as { settle_group_id?: unknown }).settle_group_id
      : "";
    return typeof id === "string" && groupIdPattern.test(id.trim())
      ? id.trim()
      : "";
  } catch {
    return "";
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleReconcile(req));
}

/// Compara os dois digests. O tamanho do header não encurta a comparação.
async function secretMatches(header: string, secret: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(header)),
    crypto.subtle.digest("SHA-256", encoder.encode(secret)),
  ]);
  return sameBytes(new Uint8Array(left), new Uint8Array(right)) &&
    secret.length > 0;
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}
