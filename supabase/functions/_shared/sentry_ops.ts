// Alerta operacional. O corpo leva só escopo e código.
// O DSN, quando existe, não entra no log nem no corpo do evento.

export type OpsEnv = { get(name: string): string | undefined };

export type OpsFetch = (
  input: string,
  init?: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
  },
) => Promise<{ ok: boolean }>;

export type OpsAlert = { scope: string; code: string };

const codePattern = /^[a-z0-9_]{1,48}$/;
const scopePattern = /^[a-z0-9-]{1,48}$/;

export async function captureOpsAlert(
  env: OpsEnv,
  fetchFn: OpsFetch,
  alert: OpsAlert,
): Promise<boolean> {
  const scope = scopePattern.test(alert.scope) ? alert.scope : "ops";
  const code = codePattern.test(alert.code) ? alert.code : "unknown";
  console.error(JSON.stringify({ scope, code }));
  const target = sentryTarget(env.get("SENTRY_DSN"));
  if (!target) return false;
  const eventId = crypto.randomUUID().replaceAll("-", "");
  const envelope = [
    JSON.stringify({ event_id: eventId }),
    JSON.stringify({ type: "event" }),
    JSON.stringify({
      event_id: eventId,
      timestamp: Date.now() / 1000,
      level: "error",
      platform: "javascript",
      message: { formatted: `${scope}: ${code}` },
      tags: { scope, code },
    }),
  ].join("\n");
  try {
    const response = await fetchFn(target.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-sentry-envelope",
        "X-Sentry-Auth":
          `Sentry sentry_version=7, sentry_key=${target.key}, sentry_client=escapematch-ops/1`,
      },
      body: envelope,
    });
    return response.ok;
  } catch {
    return false;
  }
}

function sentryTarget(
  dsn: string | undefined,
): { url: string; key: string } | null {
  const raw = (dsn ?? "").trim();
  if (!raw) return null;
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:") return null;
  if (parsed.username.length < 8 || parsed.password !== "") return null;
  if (!sentryHost(parsed.hostname)) return null;
  const project = parsed.pathname.replace(/\/+$/, "").split("/").pop() ?? "";
  if (!/^\d+$/.test(project)) return null;
  return {
    key: parsed.username,
    url: `https://${parsed.hostname}/api/${project}/envelope/`,
  };
}

function sentryHost(host: string): boolean {
  return host.endsWith(".ingest.sentry.io") ||
    host.endsWith(".ingest.us.sentry.io") ||
    host.endsWith(".ingest.de.sentry.io");
}
