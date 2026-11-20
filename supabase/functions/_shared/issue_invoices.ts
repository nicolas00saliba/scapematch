// NFS-e continua pendente. A emissão não chama provedor de pagamento.

export const invoiceEmissionSetting = "INVOICE_EMISSION";

export function invoiceEmissionEnabled(_value: string | undefined): boolean {
  return false;
}

export function shouldEmitInvoice(_input: unknown): boolean {
  return false;
}

export const invoiceAttemptLimit = 5;

export const invoiceProcessingStaleMs = 15 * 60 * 1000;

export function invoiceErrorRetryable(reason: unknown): boolean {
  return reason === "sem_certificado";
}

export function invoiceFailureReason(_error: unknown): string {
  return "nfs_e_pendente";
}

export function issuePaidInvoices(
  _admin: unknown,
  _charge: unknown,
  _options?: unknown,
): Promise<void> {
  return Promise.resolve();
}

export function retryFailedInvoices(_admin: unknown): Promise<void> {
  return Promise.resolve();
}

export function cancelInvoicesForCharge(
  _admin: unknown,
  _chargeId: string,
  _options?: unknown,
): Promise<void> {
  return Promise.resolve();
}
