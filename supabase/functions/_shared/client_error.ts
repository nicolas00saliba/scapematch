import { redactSensitive } from "./redact.ts";

const safeCode = /^[A-Za-z][A-Za-z0-9_]{0,40}$/;

export type ClientBody = { error: string; ref?: string };

export type ClientResult = { status: number; body: ClientBody };

/// Log de falha interna: função, tipo curto e id. Sem mensagem nem corpo.
export function logInternalError(scope: string, error: unknown): string {
  const ref = crypto.randomUUID();
  const name = error instanceof Error ? error.name : "";
  const code = safeCode.test(name) ? name : "unknown";
  console.error(redactSensitive(JSON.stringify({ scope, code, ref })));
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
