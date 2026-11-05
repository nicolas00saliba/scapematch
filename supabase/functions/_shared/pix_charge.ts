/// Referência estável por jogador e grupo. A chave do cliente leva timestamp
/// e muda a cada toque; esta não, então o retry acha a mesma cobrança.
export function pixExternalReference(groupId: string, userId: string): string {
  const group = groupId.trim();
  const user = userId.trim();
  if (!group || !user || /\s/.test(group) || /\s/.test(user)) {
    throw new Error("referência do Pix inválida");
  }
  return `pix:${group}:${user}`;
}

/// RECEIVED e CONFIRMED já foram pagos. O resto do Pix nasce pendente.
export function localChargeStatus(asaasStatus: string): "pending" | "paid" {
  const status = asaasStatus.trim().toUpperCase();
  if (status === "RECEIVED" || status === "CONFIRMED") return "paid";
  return "pending";
}

/// Pix pendente já criado no provedor, ainda sem o copia-e-cola.
/// Cobrança paga não fica presa à busca do QR.
export function pixNeedsQr(charge: {
  status: string;
  billing_type: string;
  provider_ref: string | null;
  qr_code: string | null;
}): boolean {
  return charge.status === "pending" &&
    charge.billing_type === "PIX" &&
    Boolean(charge.provider_ref) &&
    !charge.qr_code;
}
