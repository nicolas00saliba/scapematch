// Mesma conta de packages/dominio/lib/src/scape_points.dart.
// O banco é quem lança. Este módulo cobre o cálculo testável na função
// e confere o percentual que o SQL devolve antes de chamar o Asaas.

export const officialPointValueCents = 1;
export const officialC2cBps = 250;
export const officialB2cBps = 250;
export const officialC2bBps = 250;
export const officialB2bBps = 500;
export const officialCashbackBps = 100;
export const officialAttributionDays = 365;
export const officialHoldDays = 30;
export const officialFirstBookingDiscountBps = 2000;

export type RewardPayee = "player_points" | "venue_credit";

export type RewardLine = {
  program: "c2c" | "b2c" | "c2b" | "b2b" | "cashback";
  cents: number;
  points: number;
  payee: RewardPayee;
  reviewStatus?: "em_revisao";
};

export type AttributionSlice = {
  startsAt: string;
  endsAt: string;
  blocked?: boolean;
};

export type SpendRewardInput = {
  grossCents: number;
  commissionBps: number;
  subsidyCents?: number;
  firstBookingDiscountCents?: number;
  paidAt: string;
  playerReferrer?: AttributionSlice | null;
  playerReferrerIsVenue?: boolean;
  spendAtReferrerVenue?: boolean;
  venueReferrer?: AttributionSlice | null;
  venueReferrerIsPlayer?: boolean;
  payerCpfMissing?: boolean;
  playerReferrerCpfMissing?: boolean;
  venueReferrerCpfMissing?: boolean;
  fraudReason?: string | null;
  c2cBps?: number;
  b2cBps?: number;
  c2bBps?: number;
  b2bBps?: number;
  cashbackBps?: number;
  pointValueCents?: number;
  blockSelfPayer?: boolean;
  payerReferredAccountCap?: number;
  sameDeviceReviewThreshold?: number;
  playerPayerIsReferrer?: boolean;
  venuePayerIsReferrer?: boolean;
  payerRewardedAccounts?: number;
  playerSubjectAlreadyRewarded?: boolean;
  venueSubjectAlreadyRewarded?: boolean;
  playerDeviceCluster?: number;
  venueDeviceCluster?: number;
};

export function commissionCents(amountCents: number, basisPoints: number): number {
  return Math.floor((amountCents * basisPoints + 5000) / 10000);
}

export function attributionCovers(
  slice: AttributionSlice,
  paidAt: string,
): boolean {
  if (slice.blocked) return false;
  const paid = Date.parse(paidAt);
  return paid >= Date.parse(slice.startsAt) && paid < Date.parse(slice.endsAt);
}

export function referralFraudReason(input: {
  leftCpf?: string | null;
  rightCpf?: string | null;
  leftPhone?: string | null;
  rightPhone?: string | null;
  sharedCardToken?: boolean;
  playerCpf?: string | null;
  venueDocument?: string | null;
  venueOwnerCpf?: string | null;
}): string | null {
  if (input.sharedCardToken) return "shared_card";
  const left = digits(input.leftCpf);
  const right = digits(input.rightCpf);
  if (left && right && left === right) return "shared_cpf";
  const phoneLeft = digits(input.leftPhone);
  const phoneRight = digits(input.rightPhone);
  if (phoneLeft && phoneRight && phoneLeft === phoneRight) return "shared_phone";
  const player = digits(input.playerCpf);
  const venue = digits(input.venueDocument);
  const owner = digits(input.venueOwnerCpf);
  if (player && venue && player === venue) return "player_owns_venue";
  if (player && owner && player === owner) return "player_owns_venue";
  return null;
}

function payerBlocksReferral(input: {
  payerIsReferrer?: boolean;
  rewardedAccounts?: number;
  subjectAlreadyRewarded?: boolean;
  cap?: number;
  blockSelfPayer?: boolean;
}): boolean {
  if ((input.blockSelfPayer ?? true) && input.payerIsReferrer) return true;
  const cap = input.cap ?? 3;
  if (cap <= 0 || input.subjectAlreadyRewarded) return false;
  return (input.rewardedAccounts ?? 0) >= cap;
}

function deviceReview(
  cluster: number | undefined,
  input: SpendRewardInput,
): "em_revisao" | undefined {
  const threshold = input.sameDeviceReviewThreshold ?? 2;
  if (threshold <= 0 || (cluster ?? 0) < threshold) return undefined;
  return "em_revisao";
}

export function quoteReferralRewards(input: SpendRewardInput): RewardLine[] {
  const pointValue = input.pointValueCents ?? officialPointValueCents;
  const commission = commissionCents(input.grossCents, input.commissionBps);
  let pool = commission - (input.subsidyCents ?? 0) -
    (input.firstBookingDiscountCents ?? 0);
  if (pool < 0) pool = 0;
  const lines: RewardLine[] = [];
  const paid = input.grossCents - (input.subsidyCents ?? 0);
  const cash = takePoints(
    paid,
    input.cashbackBps ?? officialCashbackBps,
    pool,
    pointValue,
  );
  if (cash.points > 0) {
    lines.push({
      program: "cashback",
      cents: cash.cents,
      points: cash.points,
      payee: "player_points",
    });
    pool -= cash.cents;
  }
  const player = input.fraudReason ? null : input.playerReferrer;
  const playerReview = deviceReview(input.playerDeviceCluster, input);
  if (
    player && attributionCovers(player, input.paidAt) && !input.payerCpfMissing &&
    !payerBlocksReferral({
      payerIsReferrer: input.playerPayerIsReferrer,
      rewardedAccounts: input.payerRewardedAccounts,
      subjectAlreadyRewarded: input.playerSubjectAlreadyRewarded,
      cap: input.payerReferredAccountCap,
      blockSelfPayer: input.blockSelfPayer,
    })
  ) {
    if (input.playerReferrerIsVenue) {
      if (!input.spendAtReferrerVenue) {
        const cents = takeCents(input.grossCents, input.b2cBps ?? officialB2cBps, pool);
        if (cents > 0) {
          lines.push({
            program: "b2c",
            cents,
            points: 0,
            payee: "venue_credit",
            ...(playerReview ? { reviewStatus: playerReview } : {}),
          });
          pool -= cents;
        }
      }
    } else if (!input.playerReferrerCpfMissing) {
      const taken = takePoints(
        input.grossCents,
        input.c2cBps ?? officialC2cBps,
        pool,
        pointValue,
      );
      if (taken.points > 0) {
        lines.push({
          program: "c2c",
          cents: taken.cents,
          points: taken.points,
          payee: "player_points",
          ...(playerReview ? { reviewStatus: playerReview } : {}),
        });
        pool -= taken.cents;
      }
    }
  }
  const venue = input.fraudReason ? null : input.venueReferrer;
  const venueReview = deviceReview(input.venueDeviceCluster, input);
  if (
    venue && attributionCovers(venue, input.paidAt) &&
    !payerBlocksReferral({
      payerIsReferrer: input.venuePayerIsReferrer,
      rewardedAccounts: input.payerRewardedAccounts,
      subjectAlreadyRewarded: input.venueSubjectAlreadyRewarded,
      cap: input.payerReferredAccountCap,
      blockSelfPayer: input.blockSelfPayer,
    })
  ) {
    if (input.venueReferrerIsPlayer) {
      if (!input.venueReferrerCpfMissing) {
        const taken = takePoints(
          input.grossCents,
          input.c2bBps ?? officialC2bBps,
          pool,
          pointValue,
        );
        if (taken.points > 0) {
          lines.push({
            program: "c2b",
            cents: taken.cents,
            points: taken.points,
            payee: "player_points",
            ...(venueReview ? { reviewStatus: venueReview } : {}),
          });
        }
      }
    } else if ((input.firstBookingDiscountCents ?? 0) <= 0) {
      const cents = takeCents(input.grossCents, input.b2bBps ?? officialB2bBps, pool);
      if (cents > 0) {
        lines.push({
          program: "b2b",
          cents,
          points: 0,
          payee: "venue_credit",
          ...(venueReview ? { reviewStatus: venueReview } : {}),
        });
      }
    }
  }
  return lines;
}

export function subsidizedHouseSplitPercent(
  houseNetCents: number,
  chargedCents: number,
): number {
  if (chargedCents <= 0) throw new Error("cobrança sem valor");
  if (houseNetCents < 0 || houseNetCents > chargedCents) {
    throw new Error("líquido da casa não cabe");
  }
  if (houseNetCents === 0) return 0;
  const scaled = Math.ceil((houseNetCents * 1000000) / chargedCents);
  const percent = scaled / 10000;
  if (percent > 100) throw new Error("split passou de 100");
  return percent;
}

export type PointSubsidyQuote = {
  grossCents: number;
  chargedCents: number;
  subsidyCents: number;
  points: number;
  houseNetCents: number;
  commissionCents: number;
  splitPercent: number | null;
  maxPoints: number;
  backedPoints: number;
  unbackedPoints: number;
  topupCents: number;
  pointsOnly: boolean;
  limitReason: "monthly_limit" | "antifraud" | "reserve" | null;
};

export function referralBookingsForPoints(input: {
  targetPoints: number;
  grossCents: number;
  c2cBps?: number;
  pointValueCents?: number;
}): number {
  const pointValue = input.pointValueCents ?? officialPointValueCents;
  const each = Math.floor(commissionCents(input.grossCents, input.c2cBps ?? officialC2cBps) / pointValue);
  if (each <= 0) throw new Error("indicação sem ponto");
  if (input.targetPoints <= 0) return 0;
  return Math.ceil(input.targetPoints / each);
}

/// Mesma conta de quotePointSubsidy no domínio Dart.
export function quotePointSubsidy(input: {
  grossCents: number;
  commissionBps: number;
  requestedPoints: number;
  availablePoints: number;
  availableBackedPoints?: number;
  pointValueCents?: number;
  redeemMinPoints?: number;
  redeemMaxBps?: number;
  backedFullSlotEnabled?: boolean;
  freeSlotMonthlyLimit?: number;
  receiptFeeCents?: number;
  reservedBalanceCents?: number;
  freeSlotsUsedThisMonth?: number;
  backedFraudHold?: boolean;
}): PointSubsidyQuote {
  const pointValue = input.pointValueCents ?? officialPointValueCents;
  const minPoints = input.redeemMinPoints ?? 1000;
  const maxBps = input.redeemMaxBps ?? 3000;
  const monthlyLimit = input.freeSlotMonthlyLimit ?? 1;
  const feeFlat = input.receiptFeeCents ?? 0;
  const usedFreeSlots = input.freeSlotsUsedThisMonth ?? 0;
  const commission = commissionCents(input.grossCents, input.commissionBps);
  const houseNet = input.grossCents - commission;
  const classicCeiling = classicMaxPoints(
    input.grossCents,
    commission,
    input.availablePoints,
    pointValue,
    minPoints,
    maxBps,
  );
  const backedPool = clampBacked(input.availableBackedPoints, input.availablePoints);
  const unbackedPool = input.availablePoints - backedPool;
  const extensionOff = input.backedFullSlotEnabled !== true ||
    input.backedFraudHold === true ||
    monthlyLimit <= 0 ||
    usedFreeSlots >= monthlyLimit;
  if (extensionOff) {
    const reason = input.backedFullSlotEnabled !== true
      ? null
      : input.backedFraudHold === true
      ? "antifraud" as const
      : "monthly_limit" as const;
    return classicQuote({
      grossCents: input.grossCents,
      commission,
      houseNet,
      requestedPoints: input.requestedPoints,
      availablePoints: input.availablePoints,
      maxPoints: classicCeiling,
      unbackedPool,
      minPoints,
      pointValue,
      limitReason: reason,
    });
  }
  const fullPoints = Math.floor(input.grossCents / pointValue);
  const reserved = input.reservedBalanceCents ?? backedPool * pointValue;
  const ceiling = allocateFullSlot({
    want: Math.min(input.availablePoints, fullPoints),
    grossCents: input.grossCents,
    commission,
    houseNet,
    classicCeiling,
    backedPool,
    unbackedPool,
    pointValue,
    receiptFeeCents: feeFlat,
    openTopupCents: 0,
    platformCash: reserved,
    reserveCents: 0,
  });
  let maxPoints = ceiling.points;
  if (input.availablePoints < minPoints || maxPoints < minPoints) maxPoints = 0;
  const applied = allocateFullSlot({
    want: input.requestedPoints,
    grossCents: input.grossCents,
    commission,
    houseNet,
    classicCeiling,
    backedPool,
    unbackedPool,
    pointValue,
    receiptFeeCents: feeFlat,
    openTopupCents: 0,
    platformCash: reserved,
    reserveCents: 0,
  });
  let points = applied.points;
  let backedSpend = applied.backedSpend;
  let unbackedSpend = applied.unbackedSpend;
  let topup = applied.topup;
  if (points > maxPoints || points < minPoints) {
    points = 0;
    backedSpend = 0;
    unbackedSpend = 0;
    topup = 0;
  }
  const subsidy = points * pointValue;
  const charged = input.grossCents - subsidy;
  return {
    grossCents: input.grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points,
    houseNetCents: houseNet,
    commissionCents: commission,
    splitPercent: splitFor(houseNet, charged, subsidy, topup),
    maxPoints,
    backedPoints: backedSpend,
    unbackedPoints: unbackedSpend,
    topupCents: topup,
    pointsOnly: charged === 0 && subsidy > 0,
    limitReason: applied.reserveCut ? "reserve" : null,
  };
}

function classicMaxPoints(
  grossCents: number,
  commission: number,
  availablePoints: number,
  pointValue: number,
  minPoints: number,
  maxBps: number,
): number {
  const room = grossCents > 1 ? grossCents - 1 : 0;
  const percentCap = commissionCents(grossCents, maxBps);
  const maxSubsidy = Math.min(commission, room, Math.max(percentCap, 0));
  let maxPoints = Math.floor(Math.max(maxSubsidy, 0) / pointValue);
  if (availablePoints < minPoints || maxPoints < minPoints) maxPoints = 0;
  return maxPoints;
}

function classicQuote(input: {
  grossCents: number;
  commission: number;
  houseNet: number;
  requestedPoints: number;
  availablePoints: number;
  maxPoints: number;
  unbackedPool: number;
  minPoints: number;
  pointValue: number;
  limitReason: "monthly_limit" | "antifraud" | null;
}): PointSubsidyQuote {
  let points = input.requestedPoints;
  if (points < 0) points = 0;
  if (points > input.availablePoints) points = input.availablePoints;
  if (points > input.maxPoints) points = input.maxPoints;
  if (points < input.minPoints) points = 0;
  const unbackedSpend = Math.max(0, Math.min(points, input.unbackedPool));
  const subsidy = points * input.pointValue;
  const charged = input.grossCents - subsidy;
  return {
    grossCents: input.grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points,
    houseNetCents: input.houseNet,
    commissionCents: input.commission,
    splitPercent: subsidy === 0 ? null : subsidizedHouseSplitPercent(input.houseNet, charged),
    maxPoints: input.maxPoints,
    backedPoints: points - unbackedSpend,
    unbackedPoints: unbackedSpend,
    topupCents: 0,
    pointsOnly: false,
    limitReason: input.limitReason,
  };
}

function clampBacked(availableBackedPoints: number | undefined, availablePoints: number): number {
  let backed = availableBackedPoints ?? 0;
  if (backed < 0) backed = 0;
  if (backed > availablePoints) backed = availablePoints;
  return backed;
}

function splitFor(
  houseNet: number,
  charged: number,
  subsidy: number,
  topup: number,
): number | null {
  if (subsidy === 0 || charged <= 0 || topup > 0) return null;
  return subsidizedHouseSplitPercent(houseNet, charged);
}

function allocateFullSlot(input: {
  want: number;
  grossCents: number;
  commission: number;
  houseNet: number;
  classicCeiling: number;
  backedPool: number;
  unbackedPool: number;
  pointValue: number;
  receiptFeeCents: number;
  openTopupCents: number;
  platformCash: number;
  reserveCents: number;
}): {
  points: number;
  backedSpend: number;
  unbackedSpend: number;
  topup: number;
  reserveCut: boolean;
} {
  let want = input.want;
  if (want < 0) want = 0;
  const pool = input.backedPool + input.unbackedPool;
  if (want > pool) want = pool;
  const unbackedCap = Math.min(input.classicCeiling, input.unbackedPool);
  let unbackedSpend = Math.min(want, Math.max(unbackedCap, 0));
  let backedSpend = Math.min(want - unbackedSpend, input.backedPool);
  if (backedSpend < 0) backedSpend = 0;
  let reserveCut = false;
  const room = input.platformCash - input.openTopupCents - input.reserveCents;
  while (backedSpend >= 0) {
    const subsidy = (unbackedSpend + backedSpend) * input.pointValue;
    const charged = input.grossCents - subsidy;
    if (charged < 0) {
      backedSpend -= 1;
      continue;
    }
    const fee = charged === 0
      ? 0
      : Math.min(input.receiptFeeCents, charged);
    const net = charged - fee;
    if (charged > 0 && net <= 0) {
      if (backedSpend === 0) break;
      backedSpend -= 1;
      continue;
    }
    const topup = charged === 0
      ? input.houseNet
      : Math.max(0, input.houseNet - net);
    if (backedSpend === 0) {
      return {
        points: unbackedSpend,
        backedSpend: 0,
        unbackedSpend,
        topup: 0,
        reserveCut,
      };
    }
    if (
      topup > backedSpend * input.pointValue ||
      backedSpend * input.pointValue > room
    ) {
      reserveCut = true;
      if (backedSpend === 0) break;
      backedSpend -= 1;
      continue;
    }
    if (topup > 0 && topup > room) {
      reserveCut = true;
      if (backedSpend === 0) break;
      backedSpend -= 1;
      continue;
    }
    return {
      points: unbackedSpend + backedSpend,
      backedSpend,
      unbackedSpend,
      topup,
      reserveCut,
    };
  }
  return {
    points: unbackedSpend,
    backedSpend: 0,
    unbackedSpend,
    topup: 0,
    reserveCut,
  };
}

export function accrualIdempotencyKey(chargeId: string, program: string): string {
  return `accrual:${chargeId}:${program}`;
}

export function postRewardsOnce(
  existingKeys: Set<string>,
  chargeId: string,
  lines: RewardLine[],
): RewardLine[] {
  const posted: RewardLine[] = [];
  for (const line of lines) {
    const posts = line.payee === "venue_credit" ? line.cents > 0 : line.points > 0;
    if (!posts) continue;
    const key = accrualIdempotencyKey(chargeId, line.program);
    if (!existingKeys.has(key)) {
      existingKeys.add(key);
      posted.push(line);
    }
  }
  return posted;
}

export function splitMatchesSubsidy(
  splitPercent: number,
  houseNetCents: number,
  chargedCents: number,
): boolean {
  return Math.abs(splitPercent - subsidizedHouseSplitPercent(houseNetCents, chargedCents)) <=
    0.0001;
}

function takeCents(grossCents: number, bps: number, pool: number): number {
  if (pool <= 0 || bps <= 0) return 0;
  const raw = commissionCents(grossCents, bps);
  return raw > pool ? pool : raw;
}

function takePoints(
  grossCents: number,
  bps: number,
  pool: number,
  pointValue: number,
): { cents: number; points: number } {
  const room = takeCents(grossCents, bps, pool);
  const points = Math.floor(room / pointValue);
  return { cents: points * pointValue, points };
}

function digits(value: string | null | undefined): string | null {
  if (!value) return null;
  const only = value.replace(/\D/g, "");
  return only.length > 0 ? only : null;
}

/// 11 ou 14 dígitos. Asterisco é a máscara do Asaas e não compara.
export function fullPayerDocument(value: string | null | undefined): string | null {
  if (!value || value.includes("*")) return null;
  const only = digits(value);
  if (!only || (only.length !== 11 && only.length !== 14)) return null;
  return only;
}

export type PayerDocumentStatus = "matched" | "mismatch" | "unverified";

export function payerDocumentStatus(
  accountCpf: string | null | undefined,
  payerDocument: string | null | undefined,
): PayerDocumentStatus {
  const account = fullPayerDocument(accountCpf);
  const payer = fullPayerDocument(payerDocument);
  if (!account || !payer) return "unverified";
  return account === payer ? "matched" : "mismatch";
}

export function referralBenefitAllowed(
  status: string | null | undefined,
): boolean {
  return status !== "blocked-by-removed-rule";
}

/// O webhook da cobrança não traz o pagador. A consulta da transação Pix
/// traz payer.cpfCnpj e, em outro formato, externalAccount.cpfCnpj.
/// Dois números inteiros diferentes não escolhem um lado.
export function pixPayerDocument(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const record = body as Record<string, unknown>;
  const payer = nestedDocument(record.payer);
  const external = nestedDocument(record.externalAccount);
  if (payer && external && payer !== external) return null;
  return payer ?? external;
}

function nestedDocument(value: unknown): string | null {
  if (!value || typeof value !== "object") return null;
  const raw = (value as { cpfCnpj?: unknown }).cpfCnpj;
  return typeof raw === "string" ? fullPayerDocument(raw) : null;
}
