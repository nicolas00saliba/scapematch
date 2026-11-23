import { redactSensitive } from "./redact.ts";

/// Código estável devolvido ao cliente quando a PagBank falha.
export const providerUnavailable = "pagbank_unavailable";

/// Recusa do emissor. Não é indisponibilidade da PagBank.
export const cardDeclined = "card_declined";

const providerMessage =
  /^(PagBank \d+|Resposta da PagBank|PAGBANK_TOKEN ausente|PAGBANK_BASE_URL inválida|PAGBANK_ACCOUNT_ID ausente)/;

export function isProviderFailure(error: unknown): boolean {
  return error instanceof Error && providerMessage.test(error.message);
}

const providerErrorCode = /^[A-Za-z0-9_.:-]{1,80}$/;

const providerCodeAllowlist = new Set([
  "invalid_action",
  "invalid_creditCard",
  "invalid_customer",
  "invalid_value",
  "invalid_object",
  "card_declined",
]);

const emailInText = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const secretInText = /\$?aact_[A-Za-z0-9_]+/g;

export type ProviderErrorItem = { code: string; description: string };

export function providerStatus(error: unknown): number | null {
  const raw = error instanceof Error ? error.message : "";
  const match = /^PagBank (\d+)/.exec(raw);
  if (!match) return null;
  const status = Number(match[1]);
  return Number.isInteger(status) ? status : null;
}

export function providerErrorItems(error: unknown): ProviderErrorItem[] {
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
  const record = parsed as { errors?: unknown; error_messages?: unknown };
  const errors = Array.isArray(record.errors)
    ? record.errors
    : Array.isArray(record.error_messages)
    ? record.error_messages
    : [];
  const items: ProviderErrorItem[] = [];
  for (const item of errors) {
    if (!item || typeof item !== "object") continue;
    const codeRaw = (item as { code?: unknown }).code;
    const descriptionRaw = (item as { description?: unknown; message?: unknown })
      .description ?? (item as { message?: unknown }).message;
    const code = typeof codeRaw === "string" && providerErrorCode.test(codeRaw)
      ? codeRaw
      : "unknown";
    const description = sanitizeProviderDescription(
      typeof descriptionRaw === "string" ? descriptionRaw : "",
    );
    if (!description && code === "unknown") continue;
    items.push({ code, description });
  }
  return items.slice(0, 5);
}

function sanitizeProviderDescription(text: string): string {
  const cleaned = redactSensitive(text)
    .replace(emailInText, "[redacted]")
    .replace(secretInText, "[redacted]")
    .replace(/\b\d{11,14}\b/g, "[redacted]")
    .replace(/access_token|api[_-]?key|bearer\s+\S+/gi, "[redacted]")
    .slice(0, 180);
  if (cleaned.includes("@")) return "[redacted]";
  return cleaned;
}

export function isCardDeclined(error: unknown): boolean {
  const status = providerStatus(error);
  if (status !== 400 && status !== 402) return false;
  const items = providerErrorItems(error);
  if (items.some((item) => item.code === "invalid_creditCard")) return true;
  if (items.some((item) => item.code === "card_declined")) return true;
  const blob = items.map((item) => item.description).join(" ").toLowerCase();
  return blob.includes("não autoriz") || blob.includes("nao autoriz") ||
    blob.includes("recusad") || blob.includes("declin");
}

export function isDuplicateConnectEmail(error: unknown): boolean {
  return providerErrorItems(error).some((item) => {
    const blob = `${item.code} ${item.description}`.toLowerCase();
    const mentionsEmail = blob.includes("email") || blob.includes("e-mail");
    const mentionsDup = /j[aá]\s+est|em uso|exist|duplic|already|cadastr/.test(
      blob,
    );
    return mentionsEmail && mentionsDup;
  });
}

export const isDuplicateSubaccountEmail = isDuplicateConnectEmail;

export function logProviderFailure(scope: string, error: unknown): void {
  const status = providerStatus(error);
  const errors = providerErrorItems(error).map((item) => ({
    code: providerCodeAllowlist.has(item.code) ? item.code : "unlisted",
  }));
  const line = JSON.stringify({
    scope,
    code: providerUnavailable,
    status: status == null ? null : String(status),
    ...(errors.length > 0 ? { errors } : {}),
  });
  console.error(redactSensitive(line));
}

const safeCode = /^[A-Za-z][A-Za-z0-9_]{0,40}$/;

export type ClientBody = { error: string; ref?: string };
export type ClientResult = { status: number; body: ClientBody };

export function logInternalError(scope: string, error: unknown): string {
  const ref = crypto.randomUUID();
  const name = error instanceof Error ? error.name : "";
  const code = safeCode.test(name) ? name : "unknown";
  console.error(JSON.stringify({ scope, code, ref }));
  return ref;
}

export function logCaught(scope: string, error: unknown): void {
  if (isProviderFailure(error)) {
    logProviderFailure(scope, error);
    return;
  }
  logInternalError(scope, error);
}

export function storedFailure(scope: string, error: unknown): string {
  if (isProviderFailure(error)) {
    logProviderFailure(scope, error);
    return providerUnavailable;
  }
  return `internal_error:${logInternalError(scope, error)}`;
}

export function clientFailure(error: unknown, scope: string): ClientResult {
  if (isProviderFailure(error)) {
    logProviderFailure(scope, error);
    return { status: 502, body: { error: providerUnavailable } };
  }
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
  return safeClientText(error.message ?? "erro", scope);
}

export function safeClientText(message: string, scope: string): string {
  if (isProviderFailure(new Error(message)) || message.includes("PagBank ")) {
    logProviderFailure(scope, new Error(message));
    return providerUnavailable;
  }
  return message;
}
