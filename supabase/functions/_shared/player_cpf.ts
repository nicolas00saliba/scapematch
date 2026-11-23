/// 11 dígitos com os dois verificadores. CPF repetido não vale.
export function playerCpfDigits(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/\D/g, "");
  if (!/^\d{11}$/.test(digits) || /^(\d)\1{10}$/.test(digits)) return null;
  const digit = (length: number) => {
    let sum = 0;
    for (let i = 0; i < length; i++) {
      sum += Number(digits[i]) * (length + 1 - i);
    }
    const mod = (sum * 10) % 11;
    return mod === 10 ? 0 : mod;
  };
  if (digit(9) !== Number(digits[9]) || digit(10) !== Number(digits[10])) {
    return null;
  }
  return digits;
}

export const cardReregisterCode = "card_reregister";

export function chargeAsksNewCard(
  replacedId: string | null,
  savedCardId: string,
): boolean {
  return replacedId !== null && savedCardId.length > 0;
}
