// Transferência Pix da subconta Asaas. A chave da subconta só entra
// no header access_token, pelo AsaasProvider. Sem operationType, o Asaas
// pode cair em TED quando o banco não participa do Pix.

export type Receivable = {
  cents: number;
  creditDate: string;
  description: string;
};

export type FinancialMovement = {
  cents: number;
  date: string;
  description: string;
  type: string;
};

export type TransferRequest = {
  valueCents: number;
  externalReference: string;
  description: string;
  destination: "pix" | "bank";
  pixKey?: string;
  pixKeyType?: string;
  operationType?: string;
  bankCode?: string;
  agency?: string;
  accountNumber?: string;
  accountDigit?: string;
  ownerName?: string;
  ownerDocument?: string;
};

export type TransferResult = {
  id: string;
  status: "pending" | "done" | "failed" | "cancelled";
  receiptUrl: string;
  externalReference: string;
  failReason: string;
};

export type EnvLike = { get(name: string): string | undefined };

const day = /^\d{4}-\d{2}-\d{2}$/;

export function reaisToCents(value: number): number {
  if (!Number.isFinite(value)) throw new Error("valor");
  return Math.round(value * 100);
}

export function centsToReais(cents: number): number {
  return Math.round(cents) / 100;
}

export function balanceCents(body: Record<string, unknown>): number {
  const value = body.balance;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error("Resposta do Asaas sem balance");
  }
  return reaisToCents(value);
}

export function isPointsReserve(
  env: EnvLike,
  walletId: string,
  apiKey: string,
): boolean {
  const wallet = (env.get("ASAAS_POINTS_RESERVE_WALLET_ID") ?? "").trim();
  const key = (env.get("ASAAS_POINTS_RESERVE_API_KEY") ?? "").trim();
  if (wallet.length > 0 && walletId === wallet) return true;
  if (key.length > 0 && apiKey === key) return true;
  return false;
}

export function mapAsaasTransferStatus(
  status: string,
): TransferResult["status"] {
  switch (status) {
    case "DONE":
      return "done";
    case "FAILED":
      return "failed";
    case "CANCELLED":
      return "cancelled";
    default:
      return "pending";
  }
}

export function mapTransferEvent(
  event: string,
): TransferResult["status"] | null {
  switch (event) {
    case "TRANSFER_CREATED":
    case "TRANSFER_PENDING":
    case "TRANSFER_IN_BANK_PROCESSING":
    case "TRANSFER_BLOCKED":
      return "pending";
    case "TRANSFER_DONE":
      return "done";
    case "TRANSFER_FAILED":
      return "failed";
    case "TRANSFER_CANCELLED":
      return "cancelled";
    default:
      return null;
  }
}

/// O Asaas devolveu que o destino não aceita Pix. Não tentar TED.
export function isPixRejected(error: unknown): boolean {
  const raw = error instanceof Error ? error.message : "";
  if (raw === "sem pix") return true;
  if (!raw.toLowerCase().includes("pix")) return false;
  return /n[aã]o participa|n[aã]o aceit|n[aã]o suport|indispon/.test(
    raw.toLowerCase(),
  );
}

export function transferPayload(
  input: TransferRequest,
): Record<string, unknown> {
  const base: Record<string, unknown> = {
    value: centsToReais(input.valueCents),
    externalReference: input.externalReference,
    description: input.description,
    operationType: "PIX",
  };
  if (input.destination === "pix") {
    if (!input.pixKey || !input.pixKeyType) throw new Error("sem pix");
    return {
      ...base,
      pixAddressKey: input.pixKey,
      pixAddressKeyType: input.pixKeyType,
    };
  }
  if (
    !input.bankCode || !input.agency || !input.accountNumber ||
    !input.accountDigit
  ) {
    throw new Error("sem pix");
  }
  return {
    ...base,
    bankAccount: {
      bank: { code: input.bankCode },
      ownerName: input.ownerName ?? "",
      cpfCnpj: input.ownerDocument ?? "",
      agency: input.agency,
      account: input.accountNumber,
      accountDigit: input.accountDigit,
    },
  };
}

export function requestFromBank(
  bank: Record<string, unknown>,
  valueCents: number,
  externalReference: string,
): TransferRequest {
  if (text(bank.operation_type).toUpperCase() === "TED") {
    throw new Error("sem pix");
  }
  const destination = bank.destination === "bank" ? "bank" : "pix";
  return {
    valueCents,
    externalReference,
    description: "Saque EscapeMatch",
    destination,
    pixKey: text(bank.pix_key),
    pixKeyType: text(bank.pix_key_type),
    operationType: text(bank.operation_type),
    bankCode: text(bank.bank_code),
    agency: text(bank.agency),
    accountNumber: text(bank.account_number),
    accountDigit: text(bank.account_digit),
    ownerName: text(bank.owner_name),
    ownerDocument: text(bank.owner_document),
  };
}

export function parseTransfer(body: Record<string, unknown>): TransferResult {
  const id = text(body.id);
  if (!id) throw new Error("Resposta do Asaas sem id");
  return {
    id,
    status: mapAsaasTransferStatus(text(body.status)),
    receiptUrl: httpsUrl(body.transactionReceiptUrl),
    externalReference: text(body.externalReference),
    failReason: text(body.failReason).slice(0, 80),
  };
}

export function findTransferInList(
  body: Record<string, unknown>,
  externalReference: string,
): TransferResult | null {
  const rows = Array.isArray(body.data) ? body.data : [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const item = row as Record<string, unknown>;
    if (text(item.externalReference) !== externalReference) continue;
    return parseTransfer(item);
  }
  return null;
}

/// Eventos da subconta. O webhook da conta raiz não recebe o que acontece nela.
export const transferWebhookEvents = [
  "TRANSFER_CREATED",
  "TRANSFER_PENDING",
  "TRANSFER_IN_BANK_PROCESSING",
  "TRANSFER_BLOCKED",
  "TRANSFER_DONE",
  "TRANSFER_FAILED",
  "TRANSFER_CANCELLED",
] as const;

export const transferWebhookName = "EscapeMatch saques";

export type WebhookView = {
  id: string;
  url: string;
  enabled: boolean;
  interrupted: boolean;
  events: string[];
};

export function transferWebhookUrl(env: EnvLike): string {
  const explicit = (env.get("ASAAS_TRANSFER_WEBHOOK_URL") ?? "").trim();
  if (
    explicit.startsWith("https://") &&
    explicit.includes("/asaas-transfer-webhook")
  ) {
    return explicit;
  }
  const base = (env.get("SUPABASE_URL") ?? "").trim().replace(/\/$/, "");
  if (!base.startsWith("https://")) return "";
  return `${base}/functions/v1/asaas-transfer-webhook`;
}

export function webhookEmail(env: EnvLike): string {
  const email = (env.get("ASAAS_WEBHOOK_EMAIL") ?? "").trim();
  if (email.length < 6 || email.length > 200 || /\s/.test(email)) return "";
  if (!email.includes("@")) return "";
  return email;
}

/// authToken do Asaas: 32 a 255, sem espaço, e não pode ser a apiKey.
export function webhookAuthToken(env: EnvLike, apiKey = ""): string {
  const token = env.get("ASAAS_WEBHOOK_TOKEN") ?? "";
  if (token.length < 32 || token.length > 255 || /\s/.test(token)) return "";
  if (apiKey.length > 0 && token === apiKey) return "";
  return token;
}

export function transferWebhookBody(
  url: string,
  email: string,
  token: string,
): Record<string, unknown> {
  return {
    name: transferWebhookName,
    url,
    email,
    enabled: true,
    interrupted: false,
    apiVersion: 3,
    authToken: token,
    sendType: "SEQUENTIALLY",
    events: [...transferWebhookEvents],
  };
}

export function parseWebhookList(
  body: Record<string, unknown>,
): WebhookView[] {
  const rows = Array.isArray(body.data) ? body.data : [];
  const items: WebhookView[] = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const item = row as Record<string, unknown>;
    const id = text(item.id);
    const url = text(item.url);
    if (!id || !url) continue;
    const events = Array.isArray(item.events)
      ? item.events.filter((event): event is string => typeof event === "string")
      : [];
    items.push({
      id,
      url,
      enabled: item.enabled === true,
      interrupted: item.interrupted === true,
      events,
    });
  }
  return items;
}

export function webhookCoversTransfers(webhook: WebhookView, url: string): boolean {
  if (webhook.url !== url || !webhook.enabled || webhook.interrupted) return false;
  const events = new Set(webhook.events);
  return transferWebhookEvents.every((event) => events.has(event));
}

/// Cria se a URL ainda não existe. Atualiza o mesmo id se faltar evento.
/// Nunca devolve um segundo cadastro para a mesma URL.
export function nextWebhookAction(
  list: WebhookView[],
  url: string,
): { action: "create" } | { action: "update"; id: string } | { action: "ready" } {
  const match = list.find((item) => item.url === url);
  if (!match) return { action: "create" };
  if (webhookCoversTransfers(match, url)) return { action: "ready" };
  return { action: "update", id: match.id };
}

export function parsePaymentReceivables(
  body: Record<string, unknown>,
): Receivable[] {
  const rows = Array.isArray(body.data) ? body.data : [];
  const items: Receivable[] = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const item = row as Record<string, unknown>;
    if (text(item.status) !== "CONFIRMED") continue;
    const cents = moneyCents(item.netValue ?? item.value);
    const creditDate = text(item.estimatedCreditDate) || text(item.creditDate);
    if (cents <= 0 || !day.test(creditDate)) continue;
    items.push({
      cents,
      creditDate,
      description: text(item.description).slice(0, 80) || "A receber",
    });
  }
  return items;
}

export function parseFinancialTransactions(
  body: Record<string, unknown>,
): FinancialMovement[] {
  const rows = Array.isArray(body.data) ? body.data : [];
  const items: FinancialMovement[] = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const item = row as Record<string, unknown>;
    const date = text(item.date);
    if (!day.test(date)) continue;
    items.push({
      cents: moneyCents(item.value),
      date,
      description: text(item.description).slice(0, 80),
      type: text(item.type).slice(0, 40),
    });
  }
  return items;
}

/// Cobranças confirmadas e lançamentos com data futura. O extrato do
/// Asaas só traz o que já entrou; a data futura vem do lançamento agendado.
export function mergeReceivables(
  payments: Receivable[],
  movements: FinancialMovement[],
  today: string,
): Receivable[] {
  const merged = [...payments];
  for (const movement of movements) {
    if (movement.cents <= 0 || movement.date <= today) continue;
    merged.push({
      cents: movement.cents,
      creditDate: movement.date,
      description: movement.description || "A receber",
    });
  }
  merged.sort((left, right) => left.creditDate.localeCompare(right.creditDate));
  return merged;
}

function moneyCents(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return reaisToCents(value);
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function httpsUrl(value: unknown): string {
  const url = text(value);
  return url.startsWith("https://") ? url.slice(0, 400) : "";
}
