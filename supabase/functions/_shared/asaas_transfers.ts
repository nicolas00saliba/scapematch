// Transferência da subconta Asaas para Pix ou TED.
// A chave da subconta só entra no header access_token, pelo AsaasProvider.

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

export function transferPayload(
  input: TransferRequest,
): Record<string, unknown> {
  const base: Record<string, unknown> = {
    value: centsToReais(input.valueCents),
    externalReference: input.externalReference,
    description: input.description,
  };
  if (input.destination === "pix") {
    return {
      ...base,
      pixAddressKey: input.pixKey ?? "",
      pixAddressKeyType: input.pixKeyType ?? "",
    };
  }
  return {
    ...base,
    operationType: input.operationType === "TED" ? "TED" : "PIX",
    bankAccount: {
      bank: { code: input.bankCode ?? "" },
      ownerName: input.ownerName ?? "",
      cpfCnpj: input.ownerDocument ?? "",
      agency: input.agency ?? "",
      account: input.accountNumber ?? "",
      accountDigit: input.accountDigit ?? "",
    },
  };
}

export function requestFromBank(
  bank: Record<string, unknown>,
  valueCents: number,
  externalReference: string,
): TransferRequest {
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
