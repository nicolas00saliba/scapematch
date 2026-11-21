// Reserva do cartão no Mercado Pago dura 5 dias (capture=false).
// A escolha é só reservar perto da decisão do grupo, sem reautorizar.
//
// Reautorizar abriria uma segunda reserva e, se o cancelamento da
// primeira falhasse, o jogador ficaria com dois bloqueios. O token do
// cartão nasce no aparelho e não fica no servidor para uma segunda
// tentativa silenciosa.
//
// A autorização começa quando falta no máximo a janela menos a margem
// para o closes_at (ou starts_at, se o grupo não tem closes_at). A
// margem de 12 horas deixa a captura, no horário da decisão, ainda
// dentro dos 5 dias. Antes disso a função não chama o Mercado Pago.

export const cardAuthWindowMs = 5 * 24 * 60 * 60 * 1000;
export const cardAuthMarginMs = 12 * 60 * 60 * 1000;

export type CardHoldPlan = {
  authorizeNow: boolean;
  authorizeAt: string;
};

export function cardDecisionAt(group: {
  closes_at?: string | null;
  starts_at?: string | null;
}): Date | null {
  const raw = group.closes_at || group.starts_at || "";
  if (!raw) return null;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return null;
  return date;
}

/// Autoriza só dentro da janela. Fora dela devolve o instante em que
/// o aparelho deve tokenizar de novo.
export function planCardHold(now: Date, decisionAt: Date): CardHoldPlan {
  const openAt = decisionAt.getTime() - (cardAuthWindowMs - cardAuthMarginMs);
  if (now.getTime() >= openAt) {
    return { authorizeNow: true, authorizeAt: now.toISOString() };
  }
  return { authorizeNow: false, authorizeAt: new Date(openAt).toISOString() };
}
