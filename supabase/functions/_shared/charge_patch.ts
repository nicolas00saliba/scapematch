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

/// Bloqueio do split no recebimento. Não muda o status da cobrança.
export function splitDivergenceEvent(event: string): string | null {
  if (
    event === "PAYMENT_SPLIT_DIVERGENCE_BLOCK" ||
    event === "PAYMENT_SPLIT_DIVERGENCE_BLOCK_FINISHED"
  ) {
    return event;
  }
  return null;
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

/// O GET usa o id gravado na cobrança. O id do payload não entra nessa leitura.
export function paymentRefForRead(
  storedRef: string | null | undefined,
  _payloadId?: string | null,
): string | null {
  const ref = (storedRef ?? "").trim();
  return ref.length > 0 ? ref : null;
}

export type MemberPaymentSync = {
  payment_status: "pending" | "reserved" | "paid" | "released";
  refund_status: "none" | "refunded";
};

/// Mesma regra da função SQL. Estorno terminal deixa o membro released.
export function memberPaymentForStatus(status: string): MemberPaymentSync {
  if (status === "paid") {
    return { payment_status: "paid", refund_status: "none" };
  }
  if (status === "authorized") {
    return { payment_status: "reserved", refund_status: "none" };
  }
  if (status === "refunded") {
    return { payment_status: "released", refund_status: "refunded" };
  }
  if (status === "cancelled" || status === "failed") {
    return { payment_status: "released", refund_status: "none" };
  }
  return { payment_status: "pending", refund_status: "none" };
}
