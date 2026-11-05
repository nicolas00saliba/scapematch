export type ChargePatch = {
  status: string;
  paid_at?: string | null;
  refunded_at: string | null;
};

/// No estorno, `paid_at` fica de fora do update: a coluna guarda quando
/// a cobrança foi paga. O momento do estorno vai em `refunded_at`.
export function paymentChargePatch(input: {
  nextStatus: string;
  previousStatus: string;
  now: string;
}): ChargePatch {
  const patch: ChargePatch = {
    status: input.nextStatus,
    refunded_at: input.nextStatus === "refunded" ? input.now : null,
  };
  if (input.nextStatus === "paid") {
    patch.paid_at = input.now;
  } else if (
    input.nextStatus !== "refunded" && input.previousStatus !== "paid"
  ) {
    patch.paid_at = null;
  }
  return patch;
}
