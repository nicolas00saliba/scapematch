// A Public Key do Mercado Pago pode ir para o aparelho.
// O número do cartão não passa por esta função.

import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";

export function readMpPublicKey(env: EnvLike): string {
  try {
    return (env.get("MP_PUBLIC_KEY") ?? "").trim();
  } catch {
    return "";
  }
}

export function handleMpPublicKey(req: Request, env: EnvLike): Response {
  const json = bindJson(req, env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, env) });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "method" }, 405);
  }
  const publicKey = readMpPublicKey(env);
  if (publicKey.length < 8) return json({ error: "config_ausente" }, 503);
  return json({ public_key: publicKey });
}
