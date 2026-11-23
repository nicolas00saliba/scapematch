export const walletBlockedMessage = "A casa ainda não tem subconta Asaas.";
export const financeBlockedMessage = "A casa ainda não pode receber.";

/// Subconta e conta bancária (Pix ou conta) juntas. Sem as duas, não cobra.
export function paymentBlock(input: {
  status: string | null;
  walletId: string | null;
  hasBankAccount: boolean;
}): string | null {
  const wallet = (input.walletId ?? "").trim();
  if (input.status !== "approved" || !wallet) return walletBlockedMessage;
  if (!input.hasBankAccount) return financeBlockedMessage;
  return null;
}
