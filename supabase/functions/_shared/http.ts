import { redactSensitive } from "./redact.ts";

/// Origem usada quando `ALLOWED_ORIGINS` não está definida.
export const productionWebOrigin = "https://nicolas00saliba.github.io";

const allowedHeaders =
  "authorization, x-client-info, apikey, content-type, asaas-access-token";

export type EnvLike = { get(name: string): string | undefined };

/// Localhost só entra na lista quando a própria função está no Supabase local.
export function allowsLocalhostOrigins(env: EnvLike): boolean {
  const url = env.get("SUPABASE_URL") ?? "";
  return url.includes("localhost") || url.includes("127.0.0.1");
}

/// Origens exatas, separadas por vírgula. `*` não entra.
/// Sem a variável, fica só `https://nicolas00saliba.github.io`.
export function allowedOrigins(env: EnvLike): string[] {
  const raw = env.get("ALLOWED_ORIGINS");
  const source = raw?.trim() ? raw : productionWebOrigin;
  return source.split(",").map((item) => item.trim()).filter((item) =>
    item.length > 0 && item !== "*"
  );
}

export function isAllowedOrigin(origin: string | null, env: EnvLike): boolean {
  if (!origin || origin === "*") return false;
  if (allowedOrigins(env).includes(origin)) return true;
  if (!allowsLocalhostOrigins(env)) return false;
  return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}

export function corsHeadersFor(
  req: Request,
  env: EnvLike,
): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": allowedHeaders,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
  const origin = req.headers.get("Origin");
  if (origin && isAllowedOrigin(origin, env)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

export function json(
  body: unknown,
  status = 200,
  req?: Request,
  env?: EnvLike,
): Response {
  const cors = req
    ? corsHeadersFor(req, env ?? Deno.env)
    : {
      "Access-Control-Allow-Headers": allowedHeaders,
      "Vary": "Origin",
    };
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

export function bindJson(req: Request, env: EnvLike = Deno.env) {
  return (body: unknown, status = 200) => json(body, status, req, env);
}

export function publicError(message: string): string {
  return redactSensitive(message);
}

export function todayInSaoPaulo(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
  }).format(new Date());
}
