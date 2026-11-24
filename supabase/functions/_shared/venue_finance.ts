export const walletBlockedMessage = "A casa ainda não tem subconta PagBank.";
export const financeBlockedMessage = "A casa ainda não pode receber.";

/// Aprovada e com conta PagBank. O banco de saque não entra nesta trava.
export function paymentBlock(input: {
  status: string | null;
  walletId: string | null;
}): string | null {
  const wallet = (input.walletId ?? "").trim();
  if (input.status !== "approved" || !wallet) return walletBlockedMessage;
  return null;
}
