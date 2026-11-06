import { redactSensitive } from "./redact.ts";

/// Código estável devolvido ao cliente quando o provedor falha.
export const asaasUnavailable = "asaas_unavailable";

/// Recusa do emissor. Não é indisponibilidade do Asaas.
export const cardDeclined = "card_declined";

const asaasMessage =
  /^(Asaas \d+|Resposta do Asaas|ASAAS_API_KEY ausente|ASAAS_BASE_URL inválida)/;

export function isAsaasFailure(error: unknown): boolean {
  return error instanceof Error && asaasMessage.test(error.message);
}

const asaasErrorCode = /^[A-Za-z0-9_.:-]{1,80}$/;

/// Só estes códigos entram no log. O resto vira "unlisted".
const asaasCodeAllowlist = new Set([
  "invalid_action",
  "invalid_billingType",
  "invalid_cpfCnpj",
  "invalid_creditCard",
  "invalid_customer",
  "invalid_dueDate",
  "invalid_email",
  "invalid_externalReference",
  "invalid_object",
  "invalid_value",
]);
const emailInText = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const asaasKeyInText = /\$?aact_[A-Za-z0-9_]+/g;

export type AsaasErrorItem = { code: string; description: string };

export function asaasStatus(error: unknown): number | null {
  const raw = error instanceof Error ? error.message : "";
  const match = /^Asaas (\d+)/.exec(raw);
  if (!match) return null;
  const status = Number(match[1]);
  return Number.isInteger(status) ? status : null;
}

/// `errors[].code` e descrição, sem e-mail, documento nem chave.
export function asaasErrorItems(error: unknown): AsaasErrorItem[] {
  const raw = error instanceof Error ? error.message : "";
  const jsonStart = raw.indexOf("{");
  if (jsonStart < 0) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.slice(jsonStart));
  } catch {
    return [];
  }
  if (!parsed || typeof parsed !== "object") return [];
  const errors = (parsed as { errors?: unknown }).errors;
  if (!Array.isArray(errors)) return [];
  const items: AsaasErrorItem[] = [];
  for (const item of errors) {
    if (!item || typeof item !== "object") continue;
    const codeRaw = (item as { code?: unknown }).code;
    const descriptionRaw = (item as { description?: unknown }).description;
    const code = typeof codeRaw === "string" && asaasErrorCode.test(codeRaw)
      ? codeRaw
      : "unknown";
    const description = sanitizeAsaasDescription(
      typeof descriptionRaw === "string" ? descriptionRaw : "",
    );
    if (!description && code === "unknown") continue;
    items.push({ code, description });
  }
  return items.slice(0, 5);
}

function sanitizeAsaasDescription(text: string): string {
  const cleaned = redactSensitive(text)
    .replace(emailInText, "[redacted]")
    .replace(asaasKeyInText, "[redacted]")
    .replace(/\b\d{11,14}\b/g, "[redacted]")
    .replace(/access_token|api[_-]?key|bearer\s+\S+/gi, "[redacted]")
    .slice(0, 180);
  if (cleaned.includes("@")) return "[redacted]";
  return cleaned;
}

/// HTTP 400 do cartão de teste recusado, ou a mesma recusa em produção.
/// O corpo não volta para o cliente: só o código estável.
export function isCardDeclined(error: unknown): boolean {
  const status = asaasStatus(error);
  if (status !== 400 && status !== 402) return false;
  const items = asaasErrorItems(error);
  if (items.some((item) => item.code === "invalid_creditCard")) return true;
  const blob = items.map((item) => item.description).join(" ").toLowerCase();
  return blob.includes("não autoriz") || blob.includes("nao autoriz") ||
    blob.includes("recusad");
}

/// 400 de e-mail já cadastrado na conta Asaas.
export function isDuplicateSubaccountEmail(error: unknown): boolean {
  return asaasErrorItems(error).some((item) => {
    const blob = `${item.code} ${item.description}`.toLowerCase();
    const mentionsEmail = blob.includes("email") || blob.includes("e-mail");
    const mentionsDup = /j[aá]\s+est|em uso|exist|duplic|already|cadastr/.test(
      blob,
    );
    return mentionsEmail && mentionsDup;
  });
}

/// Log só com status HTTP e código da allowlist. Sem description.
export function logAsaasFailure(scope: string, error: unknown): void {
  const status = asaasStatus(error);
  const errors = asaasErrorItems(error).map((item) => ({
    code: asaasCodeAllowlist.has(item.code) ? item.code : "unlisted",
  }));
  const line = JSON.stringify({
    scope,
    code: asaasUnavailable,
    status: status == null ? null : String(status),
    ...(errors.length > 0 ? { errors } : {}),
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
