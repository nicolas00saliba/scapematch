/// Regras de dinheiro da PagBank. Puras: nenhum teste daqui chama a rede.
///
/// A casa recebe a parte dela sobre o BRUTO, em centavos fixos. A taxa da
/// PagBank sai só da comissão da EscapeMatch (conta primária). O pagamento
/// fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é
/// estornado e o cartão não é capturado.

export const holdUntilGroupConfirms =
  "O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.";

/// Teto da comissão digitada no Admin: 30%. 10000 basis points são 100%.
export const maxConfigurableCommissionBps = 3000;

/// Parcela mínima da PagBank: R$ 5,00. À vista não usa este piso.
/// https://developer.pagbank.com.br/reference/criar-transacao-com-repasse-de-taxa
export const minInstallmentParcelCents = 500;

/// 2x ou mais só vale quando cada parcela fica em pelo menos R$ 5.
export function installmentParcelTooSmall(
  amountCents: number,
  count: number,
): boolean {
  return count > 1 && amountCents < minInstallmentParcelCents * count;
}

/// Até 3x a EscapeMatch absorve o juro. Da 4ª à 12ª o juro vai para o jogador.
export const interestFreeInstallments = 3;
export const maxInstallments = 12;

/// Faixa da cotação de parcelas. Abaixo de R$ 1 e acima de R$ 5.000
/// a consulta nem sai para a PagBank.
export const minQuoteAmountCents = 100;
export const maxQuoteAmountCents = 500_000;

/// Total autorizado na PagBank. Sem a coluna nova, vale o principal.
export function captureAmountCents(row: {
  amount_cents: number;
  charged_amount_cents?: number | null;
}): number {
  const charged = row.charged_amount_cents;
  if (typeof charged === "number" && Number.isInteger(charged) && charged > 0) {
    return charged;
  }
  return row.amount_cents;
}

export function quoteAmountInRange(cents: number): boolean {
  return Number.isInteger(cents) &&
    cents >= minQuoteAmountCents &&
    cents <= maxQuoteAmountCents;
}

/// De 4x em diante o cliente tem de confirmar o total cotado.
export function quotedTotalAccepted(input: {
  installments: number;
  expectedCents: number | undefined;
  chargedCents: number;
}): boolean {
  const count = input.installments;
  const expected = input.expectedCents;
  if (count > interestFreeInstallments) {
    if (typeof expected !== "number" || !Number.isInteger(expected)) {
      return false;
    }
  }
  if (typeof expected === "number" && expected !== input.chargedCents) {
    return false;
  }
  return true;
}

/// Meio centavo sobe. A mesma conta do livro.
export function commissionCents(
  amountCents: number,
  commissionBps: number,
): number {
  if (
    !Number.isInteger(amountCents) || amountCents < 0 ||
    !Number.isInteger(commissionBps) || commissionBps < 0 ||
    commissionBps > maxConfigurableCommissionBps
  ) {
    throw new Error("invalid commission");
  }
  return Math.floor((amountCents * commissionBps + 5000) / 10000);
}

/// Parte da casa sobre o bruto, em centavos. A taxa do provedor não entra.
export function venueShareCents(
  grossCents: number,
  commissionBps: number,
): number {
  return grossCents - commissionCents(grossCents, commissionBps);
}

export type SplitParty = {
  accountId: string;
  amountCents: number;
  role: "venue" | "primary" | "extra";
};

export type FixedSplit = {
  method: "FIXED";
  chargedCents: number;
  venueCents: number;
  primaryCents: number;
  feePayer: "primary";
  receivers: SplitParty[];
};

/// FIXED em centavos. A soma é o valor cobrado do jogador. A casa leva o
/// valor exato da parte dela. O restante fica na conta primária, de onde
/// a PagBank tira as taxas. Não há `fee` no recebedor da casa.
export function fixedSplit(input: {
  chargedCents: number;
  venueCents: number;
  venueAccountId: string;
  primaryAccountId: string;
  extras?: { accountId: string; amountCents: number }[];
}): FixedSplit {
  const charged = input.chargedCents;
  const venue = input.venueCents;
  if (
    !Number.isInteger(charged) || charged <= 0 ||
    !Number.isInteger(venue) || venue < 0 || venue > charged
  ) {
    throw new Error("split");
  }
  const venueAccount = input.venueAccountId.trim();
  const primaryAccount = input.primaryAccountId.trim();
  if (!venueAccount || !primaryAccount || venueAccount === primaryAccount) {
    throw new Error("split");
  }
  const extras = (input.extras ?? []).filter((item) => item.amountCents > 0);
  let extraSum = 0;
  const receivers: SplitParty[] = [{
    accountId: venueAccount,
    amountCents: venue,
    role: "venue",
  }];
  for (const extra of extras) {
    if (!Number.isInteger(extra.amountCents) || extra.amountCents < 0) {
      throw new Error("split");
    }
    const accountId = extra.accountId.trim();
    if (!accountId || accountId === venueAccount || accountId === primaryAccount) {
      throw new Error("split");
    }
    extraSum += extra.amountCents;
    receivers.push({
      accountId,
      amountCents: extra.amountCents,
      role: "extra",
    });
  }
  const primary = charged - venue - extraSum;
  if (primary < 0) throw new Error("split");
  receivers.push({
    accountId: primaryAccount,
    amountCents: primary,
    role: "primary",
  });
  const sum = receivers.reduce((total, item) => total + item.amountCents, 0);
  if (sum !== charged) throw new Error("split");
  return {
    method: "FIXED",
    chargedCents: charged,
    venueCents: venue,
    primaryCents: primary,
    feePayer: "primary",
    receivers,
  };
}

/// Corpo `splits` da PagBank. Custódia em todo recebedor: o valor fica HELD
/// até o grupo confirmar. A casa não carrega taxa.
export function pagbankSplitBody(split: FixedSplit): Record<string, unknown> {
  return {
    method: "FIXED",
    receivers: split.receivers.map((item) => ({
      account: { id: item.accountId },
      amount: { value: item.amountCents },
      reason: item.role === "venue"
        ? "Repasse da casa"
        : item.role === "primary"
        ? "Comissão EscapeMatch"
        : "Ajuste",
      configurations: {
        custody: { apply: true },
      },
    })),
  };
}

export type InstallmentCharge = {
  installments: number;
  amountCents: number;
  buyerInterestCents: number;
  merchantAbsorbsInterest: boolean;
};

export type InstallmentOption = InstallmentCharge & { enabled: boolean };

/// Grade de 1x a 12x. 2x ou mais só habilita com parcela de pelo menos R$ 5.
/// De 4x a 12x também precisa do juro cotado do comprador.
export function installmentMenu(input: {
  principalCents: number;
  interestByCount?: Readonly<Record<number, number>>;
}): InstallmentOption[] {
  const principal = input.principalCents;
  if (!Number.isInteger(principal) || principal <= 0) {
    throw new Error("valor");
  }
  const quoted = input.interestByCount ?? {};
  const options: InstallmentOption[] = [];
  for (let count = 1; count <= maxInstallments; count++) {
    if (count <= interestFreeInstallments) {
      if (installmentParcelTooSmall(principal, count)) {
        options.push({
          installments: count,
          amountCents: principal,
          buyerInterestCents: 0,
          merchantAbsorbsInterest: true,
          enabled: false,
        });
        continue;
      }
      options.push({
        ...installmentCharge({ principalCents: principal, installments: count }),
        enabled: true,
      });
      continue;
    }
    const interest = quoted[count];
    if (interest == null || !Number.isInteger(interest) || interest < 0) {
      options.push({
        installments: count,
        amountCents: principal,
        buyerInterestCents: 0,
        merchantAbsorbsInterest: false,
        enabled: false,
      });
      continue;
    }
    const total = principal + interest;
    if (installmentParcelTooSmall(total, count)) {
      options.push({
        installments: count,
        amountCents: total,
        buyerInterestCents: interest,
        merchantAbsorbsInterest: false,
        enabled: false,
      });
      continue;
    }
    options.push({
      ...installmentCharge({
        principalCents: principal,
        installments: count,
        buyerInterestCents: interest,
      }),
      enabled: true,
    });
  }
  return options;
}

/// 1 a 3x: o valor cobrado é o principal e o objeto de juro do comprador
/// não vai no pedido. 4 a 12x: o juro cotado na API entra no valor e em
/// `fees.buyer.interest`. Parcela abaixo de R$ 5 recusa a cobrança.
export function installmentCharge(input: {
  principalCents: number;
  installments: number;
  buyerInterestCents?: number;
}): InstallmentCharge {
  const principal = input.principalCents;
  const count = input.installments;
  if (!Number.isInteger(principal) || principal <= 0) {
    throw new Error("valor");
  }
  if (!Number.isInteger(count) || count < 1 || count > maxInstallments) {
    throw new Error("parcelas");
  }
  if (count <= interestFreeInstallments) {
    const plan: InstallmentCharge = {
      installments: count,
      amountCents: principal,
      buyerInterestCents: 0,
      merchantAbsorbsInterest: true,
    };
    if (installmentParcelTooSmall(plan.amountCents, count)) {
      throw new Error("parcelas");
    }
    return plan;
  }
  const interest = input.buyerInterestCents ?? 0;
  if (!Number.isInteger(interest) || interest < 0) throw new Error("juros");
  const plan: InstallmentCharge = {
    installments: count,
    amountCents: principal + interest,
    buyerInterestCents: interest,
    merchantAbsorbsInterest: false,
  };
  if (installmentParcelTooSmall(plan.amountCents, count)) {
    throw new Error("parcelas");
  }
  return plan;
}

/// `amount` do charge. Sem juro do comprador nas parcelas que a casa absorve.
export function chargeAmountBody(
  plan: InstallmentCharge,
): Record<string, unknown> {
  const amount: Record<string, unknown> = {
    value: plan.amountCents,
    currency: "BRL",
  };
  if (!plan.merchantAbsorbsInterest) {
    amount.fees = {
      buyer: {
        interest: {
          total: plan.buyerInterestCents,
          installments: plan.installments - interestFreeInstallments,
        },
      },
    };
  }
  return amount;
}

export type GroupMoneyAction =
  | "release_custody"
  | "refund_pix"
  | "void_card"
  | "cancel_pending_pix"
  | "none";

/// Confirmação solta a custódia. Sem confirmação, Pix pago é estornado
/// (o saldo pode sair do HELD) e cartão autorizado não é capturado.
export function groupPaymentAction(input: {
  confirmed: boolean;
  billingType: string;
  status: string;
}): GroupMoneyAction {
  const billing = input.billingType.trim().toUpperCase();
  const status = input.status.trim().toLowerCase();
  if (status === "refunded" || status === "cancelled" || status === "failed") {
    return "none";
  }
  if (input.confirmed) {
    if (status === "paid" || status === "authorized") return "release_custody";
    return "none";
  }
  if (billing === "PIX" && status === "paid") return "refund_pix";
  if (billing === "CREDIT_CARD" && status === "authorized") return "void_card";
  if (billing === "PIX" && (status === "pending" || status === "creating")) {
    return "cancel_pending_pix";
  }
  return "none";
}

/// Procura o juro do comprador na resposta de `/charges/fees/calculate`.
export function buyerInterestFromQuote(
  body: unknown,
  installments: number,
): number | null {
  const found = findPlan(body, installments);
  if (!found) return null;
  if (found.interestFree === true) return 0;
  return found.interestCents;
}

type PlanHit = { interestFree: boolean; interestCents: number | null };

function findPlan(node: unknown, installments: number): PlanHit | null {
  if (!node || typeof node !== "object") return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const hit = findPlan(item, installments);
      if (hit) return hit;
    }
    return null;
  }
  const record = node as Record<string, unknown>;
  const count = numberField(record.installments) ?? numberField(record.quantity);
  if (count === installments) {
    const interestFree = record.interest_free === true;
    const interest = readInterest(record);
    if (interestFree || interest != null) {
      return { interestFree, interestCents: interest ?? 0 };
    }
  }
  for (const value of Object.values(record)) {
    const hit = findPlan(value, installments);
    if (hit) return hit;
  }
  return null;
}

function readInterest(record: Record<string, unknown>): number | null {
  const amount = record.amount;
  if (amount && typeof amount === "object") {
    const fees = (amount as Record<string, unknown>).fees;
    if (fees && typeof fees === "object") {
      const buyer = (fees as Record<string, unknown>).buyer;
      if (buyer && typeof buyer === "object") {
        const interest = (buyer as Record<string, unknown>).interest;
        if (interest && typeof interest === "object") {
          const total = numberField((interest as Record<string, unknown>).total);
          if (total != null) return total;
        }
      }
    }
  }
  const direct = record.interest;
  if (direct && typeof direct === "object") {
    const total = numberField((direct as Record<string, unknown>).total);
    if (total != null) return total;
  }
  return null;
}

function numberField(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  return null;
}
