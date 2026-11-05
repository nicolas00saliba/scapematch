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

export type PixReservationAction = "create" | "reuse" | "busy" | "refuse";

/// Quem inseriu a linha cria o Pix. Quem acha provider_ref reaproveita
/// e não troca o id. Linha alheia sem id ainda está em criação.
export function pixReservationAction(input: {
  inserted: boolean;
  providerRef: string | null;
  billingType: string;
}): PixReservationAction {
  if (input.billingType !== "PIX") return "refuse";
  if (input.providerRef) return "reuse";
  if (input.inserted) return "create";
  return "busy";
}

export type PixExpectation = {
  customer: string;
  valueCents: number;
  walletId: string;
  percentualValue: number;
};

/// Customer, valor, split e status precisam bater antes de reaproveitar.
export function pixMatchesCharge(
  remote: {
    customer?: unknown;
    value?: unknown;
    status?: unknown;
    billingType?: unknown;
    split?: unknown;
  },
  expected: PixExpectation,
): boolean {
  if (remote.billingType !== "PIX") return false;
  if (remote.customer !== expected.customer) return false;
  const cents = Math.round(Number(remote.value) * 100);
  if (!Number.isFinite(cents) || cents !== expected.valueCents) return false;
  const status = String(remote.status ?? "").toUpperCase();
  if (
    !["PENDING", "OVERDUE", "CONFIRMED", "RECEIVED", "AUTHORIZED"].includes(
      status,
    )
  ) {
    return false;
  }
  if (!Array.isArray(remote.split)) return false;
  const house = remote.split.find((item) => {
    if (!item || typeof item !== "object") return false;
    return (item as { walletId?: unknown }).walletId === expected.walletId;
  }) as { percentualValue?: unknown } | undefined;
  if (!house) return false;
  const percent = Number(house.percentualValue);
  return Number.isFinite(percent) &&
    Math.abs(percent - expected.percentualValue) <= 0.001;
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
