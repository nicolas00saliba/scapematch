export type LedgerLine = {
  venue_id: string;
  group_id: string;
  user_id: string;
  account: string;
  direction: string;
  kind: string;
  amount_cents: number;
  payment_charge_id: string;
};

export type LedgerWriteError = { code?: string; message?: string } | null;

export type LedgerTable = {
  insert(row: LedgerLine): PromiseLike<{ error: LedgerWriteError }>;
  upsert(
    row: LedgerLine,
    options: { onConflict: string; ignoreDuplicates: boolean },
  ): PromiseLike<{ error: LedgerWriteError }>;
};

export const ledgerConflictTarget = "payment_charge_id,kind,direction";

export function isUniqueViolation(error: LedgerWriteError): boolean {
  if (!error) return false;
  if (error.code === "23505") return true;
  const message = error.message ?? "";
  return message.includes("23505") ||
    message.toLowerCase().includes("duplicate key");
}

/// O upsert com `onConflict` só funciona depois da migração do índice.
/// Sem o índice, o Postgres responde 42P10 e o insert simples ainda vale.
export function missingConflictTarget(error: LedgerWriteError): boolean {
  if (!error) return false;
  if (error.code === "42P10") return true;
  const message = (error.message ?? "").toLowerCase();
  return message.includes("42p10") || message.includes("on conflict");
}

const sqlState = /^[0-9A-Z]{5}$/;

/// Só o SQLSTATE. A mensagem do Postgres pode trazer id, e-mail ou valor.
function logLedgerWriteFailure(error: { code?: string }): void {
  const code = error.code && sqlState.test(error.code) ? error.code : "unknown";
  console.error(JSON.stringify({ scope: "ledger", code }));
}

function rejectLedgerWrite(error: { code?: string }): never {
  logLedgerWriteFailure(error);
  throw new Error("ledger_write_failed");
}

/// Uma linha por cobrança, kind e direção. `23505` é sucesso idempotente.
/// Qualquer outro erro de escrita é logado (só o código) e lançado.
export async function insertLedgerLine(
  table: LedgerTable,
  row: LedgerLine,
): Promise<"inserted" | "duplicate"> {
  const conflict = await table.upsert(row, {
    onConflict: ledgerConflictTarget,
    ignoreDuplicates: true,
  });
  if (!conflict.error) return "inserted";
  if (isUniqueViolation(conflict.error)) return "duplicate";
  if (!missingConflictTarget(conflict.error)) rejectLedgerWrite(conflict.error);
  const inserted = await table.insert(row);
  if (!inserted.error) return "inserted";
  if (isUniqueViolation(inserted.error)) return "duplicate";
  rejectLedgerWrite(inserted.error ?? {});
}
