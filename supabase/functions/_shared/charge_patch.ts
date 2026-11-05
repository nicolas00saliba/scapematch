export const chargeTransitions: Record<string, readonly string[]> = {
  creating: [
    "pending",
    "authorized",
    "paid",
    "refunded",
    "cancelled",
    "failed",
  ],
  pending: ["authorized", "paid", "refunded", "cancelled", "failed"],
  authorized: ["paid", "refunded", "cancelled", "failed"],
  paid: ["refunded"],
};

const terminal = new Set(["refunded", "cancelled", "failed"]);

/// refunded, cancelled e failed não saem do lugar. O resto só anda
/// pela matriz. Status igual é replay e não conta como mudança.
export function paymentTransition(current: string, requested: string): string {
  if (current === requested) return current;
  if (terminal.has(current)) return current;
  const allowed = chargeTransitions[current] ?? [];
  return allowed.includes(requested) ? requested : current;
}

export type ChargePatch = {
  status: string;
  paid_at?: string;
  refunded_at?: string;
};

/// paid_at e refunded_at entram só quando nascem. Replay usa o valor
/// que já estava (coalesce): não reescreve e não apaga.
export function paymentChargePatch(input: {
  nextStatus: string;
  previousStatus: string;
  now: string;
  paidAt?: string | null;
  refundedAt?: string | null;
}): ChargePatch {
  const status = paymentTransition(input.previousStatus, input.nextStatus);
  const patch: ChargePatch = { status };
  if (status === "paid") {
    patch.paid_at = input.paidAt ?? input.now;
  }
  if (status === "refunded") {
    patch.refunded_at = input.refundedAt ?? input.now;
  }
  return patch;
}

/// O que o webhook pediu. null = evento que não move a cobrança.
export function requestedChargeStatus(
  event: string,
  paymentStatus: string,
): string | null {
  if (event === "PAYMENT_REFUNDED" || paymentStatus === "REFUNDED") {
    return "refunded";
  }
  if (
    event === "PAYMENT_RECEIVED" || event === "PAYMENT_CONFIRMED" ||
    paymentStatus === "RECEIVED" || paymentStatus === "CONFIRMED"
  ) {
    return "paid";
  }
  if (event === "PAYMENT_AUTHORIZED" || paymentStatus === "AUTHORIZED") {
    return "authorized";
  }
  return null;
}

/// Status confirmado no GET /payments/{id}. null = não aplicar.
export function confirmedChargeStatus(asaasStatus: string): string | null {
  switch (asaasStatus.trim().toUpperCase()) {
    case "REFUNDED":
      return "refunded";
    case "RECEIVED":
    case "CONFIRMED":
      return "paid";
    case "AUTHORIZED":
      return "authorized";
    case "PENDING":
    case "OVERDUE":
      return "pending";
    default:
      return null;
  }
}

export function movesMoney(status: string | null): boolean {
  return status === "paid" || status === "refunded";
}
