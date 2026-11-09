/// 55P03 é lock_timeout. 40001 é serialization_failure.
/// Os dois desfazem a transação. Repetir a mesma chave não cobra duas vezes.

export class DbRpcError extends Error {
  readonly code: string;

  constructor(code: string) {
    super("erro");
    this.name = "DbRpcError";
    this.code = code;
  }
}

export function isSerializationConflict(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as { code?: unknown; message?: unknown };
  const code = typeof record.code === "string" ? record.code : "";
  if (code === "55P03" || code === "40001") return true;
  const message = typeof record.message === "string" ? record.message : "";
  const lower = message.toLowerCase();
  return message.includes("55P03") || message.includes("40001") ||
    lower.includes("lock timeout") ||
    lower.includes("could not serialize");
}

export async function retrySerialization<T>(
  work: () => Promise<T>,
  attempts = 3,
): Promise<T> {
  let last: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await work();
    } catch (error) {
      last = error;
      if (!isSerializationConflict(error) || attempt === attempts) throw error;
    }
  }
  throw last;
}
