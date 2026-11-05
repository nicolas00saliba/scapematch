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

export function clientFailure(
  error: unknown,
  scope: string,
): { status: number; error: string } {
  if (isAsaasFailure(error)) {
    logAsaasFailure(scope, error);
    return { status: 502, error: asaasUnavailable };
  }
  if (error instanceof Error && error.message === "cartão não encontrado") {
    return { status: 403, error: "cartão não encontrado" };
  }
  return { status: 500, error: "erro" };
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
