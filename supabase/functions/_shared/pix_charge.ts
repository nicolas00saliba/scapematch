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

export type PixReservationAction =
  | "create"
  | "reuse"
  | "reclaim"
  | "busy"
  | "refuse";

export const pixLeaseMs = 2 * 60 * 1000;

/// Sem data, ou com mais de 2 minutos, a reserva pode ser assumida.
export function pixLeaseExpired(
  reservedAt: string | null,
  nowMs: number,
): boolean {
  if (!reservedAt) return true;
  const at = Date.parse(reservedAt);
  if (!Number.isFinite(at)) return true;
  return nowMs - at >= pixLeaseMs;
}

/// Quem inseriu cria o Pix. provider_ref existente não é trocado.
/// Reserva vencida pede busca no Asaas; reserva fresca fica busy.
export function pixReservationAction(input: {
  inserted: boolean;
  providerRef: string | null;
  billingType: string;
  leaseExpired?: boolean;
}): PixReservationAction {
  if (input.billingType !== "PIX") return "refuse";
  if (input.providerRef) return "reuse";
  if (input.inserted) return "create";
  if (input.leaseExpired) return "reclaim";
  return "busy";
}

export type CardSwitchDecision =
  | "proceed"
  | "cancel_pix"
  | "drop_lease"
  | "refuse";

/// Pix pendente com id é cancelado e confirmado antes de virar cartão.
/// Pix pago ou reserva fresca sem id recusa. Nunca troca o provider_ref no escuro.
export function cardSwitchDecision(
  input: {
    billingType: string;
    status: string;
    providerRef: string | null;
    leaseExpired?: boolean;
  } | null,
): CardSwitchDecision {
  if (!input) return "proceed";
  if (input.billingType !== "PIX") {
    if (input.providerRef) return "refuse";
    if (input.status === "creating") {
      return input.leaseExpired ? "drop_lease" : "refuse";
    }
    return "proceed";
  }
  if (input.status === "pending" || input.status === "creating") {
    if (input.providerRef) return "cancel_pix";
    if (input.leaseExpired) return "drop_lease";
    return "refuse";
  }
  return "refuse";
}

/// CONFIRMED e RECEIVED já capturaram. A compensação é estorno.
/// AUTHORIZED ainda é pré-autorização e também sai com refund.
export function lostAttemptCompensation(
  status: string,
): "refund" | "cancel" | "none" {
  const upper = status.trim().toUpperCase();
  if (upper === "CONFIRMED" || upper === "RECEIVED") return "refund";
  if (
    upper === "REFUNDED" || upper === "DELETED" || upper === "CANCELED" ||
    upper === "CANCELLED"
  ) {
    return "none";
  }
  return "cancel";
}

/// 4xx do Asaas: a cobrança não foi criada. Timeout e 5xx ficam no lease.
export function releaseReservationOnError(error: unknown): boolean {
  const raw = error instanceof Error ? error.message : "";
  const match = /^Asaas (\d+)/.exec(raw);
  if (!match) return false;
  const status = Number(match[1]);
  return status >= 400 && status < 500;
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
