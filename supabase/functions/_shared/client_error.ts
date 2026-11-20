import { redactSensitive } from "./redact.ts";

const safeCode = /^[A-Za-z][A-Za-z0-9_]{0,40}$/;

export type ClientBody = { error: string; ref?: string };

export type ClientResult = { status: number; body: ClientBody };

/// Mensagem curta para o log do create-charge. PAN, token e segredo saem.
export function loggedErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : "";
  return redactSensitive(raw)
    .replace(/\b(?:APP_USR|TEST)-[A-Za-z0-9_-]+/g, "[redacted]")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .slice(0, 240);
}

/// Log de falha interna: função, tipo curto e id. O create-charge também
/// grava a mensagem já mascarada. Os outros escopos continuam sem mensagem.
export function logInternalError(scope: string, error: unknown): string {
  const ref = crypto.randomUUID();
  const name = error instanceof Error ? error.name : "";
  const code = safeCode.test(name) ? name : "unknown";
  const entry: Record<string, string> = { scope, code, ref };
  if (scope === "create-charge") entry.message = loggedErrorMessage(error);
  console.error(redactSensitive(JSON.stringify(entry)));
  return ref;
}

export function logCaught(scope: string, error: unknown): void {
  logInternalError(scope, error);
}

/// Texto gravado no banco. Não leva a mensagem original.
export function storedFailure(scope: string, error: unknown): string {
  return `internal_error:${logInternalError(scope, error)}`;
}

export function clientFailure(error: unknown, scope: string): ClientResult {
  if (error instanceof Error && error.message === "cartão não encontrado") {
    return { status: 403, body: { error: "cartão não encontrado" } };
  }
  const ref = logInternalError(scope, error);
  return { status: 500, body: { error: "internal_error", ref } };
}

export function clientDbError(
  error: { message?: string },
  scope: string,
): string {
  const message = error.message ?? "erro";
  if (message.length > 80) {
    logInternalError(scope, new Error("db"));
    return "erro";
  }
  return message;
}
