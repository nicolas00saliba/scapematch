// Solta o Pix que o Asaas já apagou. Sem a função nova no banco, o
// service role faz o mesmo update: QR fora, lease vencido, Pix continua Pix.

const missingFunction = new Set(["PGRST202", "42883"]);

// deno-lint-ignore no-explicit-any
type Admin = any;

export async function detachGonePix(
  admin: Admin,
  chargeId: string,
  providerRef: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("detach_gone_pix", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
  });
  if (!error) {
    return typeof data === "string" && data.length > 0 ? data : null;
  }
  const code = typeof error.code === "string" ? error.code : "";
  if (!missingFunction.has(code)) throw new Error("erro");
  return detachWithoutFunction(admin, chargeId, providerRef);
}

async function detachWithoutFunction(
  admin: Admin,
  chargeId: string,
  providerRef: string,
): Promise<string | null> {
  const found = await admin
    .from("payment_charges")
    .select("status, billing_type, provider_ref")
    .eq("id", chargeId)
    .maybeSingle();
  if (found.error) throw new Error("erro");
  const row = found.data as {
    status?: string;
    billing_type?: string;
    provider_ref?: string | null;
  } | null;
  if (
    !row ||
    row.billing_type !== "PIX" ||
    row.provider_ref !== providerRef ||
    (row.status !== "pending" && row.status !== "creating")
  ) {
    return null;
  }
  const attemptId = crypto.randomUUID();
  const updated = await admin
    .from("payment_charges")
    .update({
      provider_ref: null,
      qr_code: null,
      qr_code_base64: null,
      status: "creating",
      reserved_at: new Date(Date.now() - 3 * 60 * 1000).toISOString(),
      attempt_id: attemptId,
    })
    .eq("id", chargeId)
    .eq("provider_ref", providerRef)
    .eq("billing_type", "PIX")
    .select("id");
  if (updated.error) throw new Error("erro");
  const rows = Array.isArray(updated.data) ? updated.data : [];
  return rows.length > 0 ? attemptId : null;
}
