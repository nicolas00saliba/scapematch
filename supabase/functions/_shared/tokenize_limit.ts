export const tokenizeLimitedMessage =
  "Muitas tentativas. Tente de novo mais tarde.";

/// Registra a decisão antes do Asaas. Se a claim recusar, a tokenização não roda.
export async function gateTokenize(
  claim: () => Promise<boolean>,
  tokenize: () => Promise<void>,
): Promise<"limited" | "ok"> {
  const allowed = await claim();
  if (!allowed) return "limited";
  await tokenize();
  return "ok";
}
