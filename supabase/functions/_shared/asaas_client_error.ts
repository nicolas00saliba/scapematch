import { redactSensitive } from "./redact.ts";

/// Código estável devolvido ao cliente quando o provedor falha.
export const asaasUnavailable = "asaas_unavailable";

const asaasMessage =
  /^(Asaas \d+|Resposta do Asaas|ASAAS_API_KEY ausente|ASAAS_BASE_URL inválida)/;

export function isAsaasFailure(error: unknown): boolean {
  return error instanceof Error && asaasMessage.test(error.message);
}

/// Log só com o código e o status HTTP. O corpo do provedor fica de fora.
export function logAsaasFailure(scope: string, error: unknown): void {
  const raw = error instanceof Error ? error.message : "";
  const status = /^Asaas (\d+)/.exec(raw)?.[1];
  const line = JSON.stringify({
    scope,
    code: asaasUnavailable,
    status: status ?? null,
  });
  console.error(redactSensitive(line));
}

const safeCode = /^[A-Za-z][A-Za-z0-9_]{0,40}$/;

export type ClientBody = { error: string; ref?: string };

export type ClientResult = { status: number; body: ClientBody };

/// Log de falha interna: função, tipo curto e id. Sem mensagem nem corpo.
export function logInternalError(scope: string, error: unknown): string {
  const ref = crypto.randomUUID();
  const name = error instanceof Error ? error.name : "";
  const code = safeCode.test(name) ? name : "unknown";
  console.error(JSON.stringify({ scope, code, ref }));
  return ref;
}

/// Asaas continua no log do provedor. O resto vira erro interno.
export function logCaught(scope: string, error: unknown): void {
  if (isAsaasFailure(error)) {
    logAsaasFailure(scope, error);
    return;
  }
  logInternalError(scope, error);
}

/// Texto gravado no banco. Não leva a mensagem original.
export function storedFailure(scope: string, error: unknown): string {
  if (isAsaasFailure(error)) {
    logAsaasFailure(scope, error);
    return asaasUnavailable;
  }
  return `internal_error:${logInternalError(scope, error)}`;
}

export function clientFailure(error: unknown, scope: string): ClientResult {
  if (isAsaasFailure(error)) {
    logAsaasFailure(scope, error);
    return { status: 502, body: { error: asaasUnavailable } };
  }
  if (error instanceof Error && error.message === "cartão não encontrado") {
    return { status: 403, body: { error: "cartão não encontrado" } };
  }
  const ref = logInternalError(scope, error);
  return { status: 500, body: { error: "internal_error", ref } };
}

/// Mensagem de erro do banco, sem texto do provedor.
export function clientDbError(
  error: { message?: string },
  scope: string,
): string {
  return safeClientText(error.message ?? "erro", scope);
}

/// Troca texto do provedor que tenha vazado numa mensagem já pronta.
export function safeClientText(message: string, scope: string): string {
  if (isAsaasFailure(new Error(message)) || message.includes("Asaas ")) {
    logAsaasFailure(scope, new Error(message));
    return asaasUnavailable;
  }
  return message;
}
