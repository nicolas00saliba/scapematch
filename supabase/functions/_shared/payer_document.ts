import { documentHash } from "./payer_identity.ts";
import { payerDocumentStatus, pixPayerDocument } from "./scape_points.ts";

type Status = "matched" | "mismatch" | "unverified";

// O cliente do Supabase e o dublê dos testes. O tipo gerado estoura a checagem.
// deno-lint-ignore no-explicit-any
type Admin = any;

type PixReader = {
  readPayment(paymentId: string): Promise<Record<string, unknown>>;
  getPixTransaction(id: string): Promise<Record<string, unknown>>;
};

/// Antes de lançar a recompensa. Não guarda o documento.
/// Falha de rede vira não verificado: a reserva segue e uma consulta
/// seguinte ainda pode confirmar.
export async function syncPayerDocument(
  admin: Admin,
  asaas: PixReader | undefined,
  charge: { id: string; user_id: string; billing_type: string; provider_ref: string | null },
  remote?: Record<string, unknown> | null,
): Promise<Status> {
  const current = await currentStatus(admin, charge.id);
  if (current === "matched" || current === "mismatch") return current;
  if (charge.billing_type !== "PIX") {
    return await record(admin, charge.id, current ?? "unverified");
  }
  const account = await accountCpf(admin, charge.user_id);
  let payer: string | null = null;
  try {
    const payment = remote ??
      (asaas && charge.provider_ref
        ? await asaas.readPayment(charge.provider_ref)
        : null);
    const pixId = pixTransactionId(payment);
    if (asaas && pixId) {
      payer = pixPayerDocument(await asaas.getPixTransaction(pixId));
    }
  } catch (_error) {
    payer = null;
  }
  const status = payerDocumentStatus(account, payer);
  const hash = await documentHash(payer);
  if (hash) {
    await admin.rpc("record_payer_identity", {
      p_charge_id: charge.id,
      p_document_hash: hash,
      p_card_key: null,
    });
  }
  return await record(admin, charge.id, status);
}

export function pixTransactionId(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const value = (body as { pixTransaction?: unknown }).pixTransaction;
  if (typeof value !== "string") return null;
  const id = value.trim();
  return id.length > 0 ? id : null;
}

async function currentStatus(admin: Admin, chargeId: string): Promise<Status | null> {
  const { data } = await admin
    .from("payment_charges")
    .select("payer_document_status")
    .eq("id", chargeId)
    .maybeSingle();
  const status = data && typeof data === "object"
    ? (data as { payer_document_status?: unknown }).payer_document_status
    : null;
  if (status === "matched" || status === "mismatch" || status === "unverified") {
    return status;
  }
  return null;
}

async function accountCpf(admin: Admin, userId: string): Promise<string | null> {
  const { data } = await admin
    .from("profiles")
    .select("cpf")
    .eq("id", userId)
    .maybeSingle();
  const cpf = data && typeof data === "object"
    ? (data as { cpf?: unknown }).cpf
    : null;
  return typeof cpf === "string" ? cpf : null;
}

async function record(admin: Admin, chargeId: string, status: Status): Promise<Status> {
  const { data, error } = await admin.rpc("record_payer_document_status", {
    p_charge_id: chargeId,
    p_status: status,
  });
  if (error) return status;
  if (data === "matched" || data === "mismatch" || data === "unverified") {
    return data;
  }
  return status;
}
