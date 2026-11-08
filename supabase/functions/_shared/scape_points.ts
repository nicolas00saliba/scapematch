// Mesma conta de packages/dominio/lib/src/scape_points.dart.
// O banco é quem lança. Este módulo cobre o cálculo testável na função
// e confere o percentual que o SQL devolve antes de chamar o Asaas.

export const officialPointValueCents = 1;
export const officialC2cBps = 250;
export const officialB2cBps = 250;
export const officialC2bBps = 250;
export const officialB2bBps = 500;
export const officialAttributionDays = 365;
export const officialHoldDays = 30;
export const officialMonthlyReferralCap = 20;
export const officialFirstBookingDiscountBps = 2000;

export type RewardPayee = "player_points" | "venue_credit";

export type RewardLine = {
  program: "c2c" | "b2c" | "c2b" | "b2b";
  cents: number;
  points: number;
  payee: RewardPayee;
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
  paidAt: string;
  playerReferrer?: AttributionSlice | null;
  playerReferrerIsVenue?: boolean;
  spendAtReferrerVenue?: boolean;
  venueReferrer?: AttributionSlice | null;
  venueReferrerIsPlayer?: boolean;
  payerCustomerRank?: number;
  payerCpfMissing?: boolean;
  playerReferrerCpfMissing?: boolean;
  venueReferrerCpfMissing?: boolean;
  fraudReason?: string | null;
  c2cBps?: number;
  b2cBps?: number;
  c2bBps?: number;
  b2bBps?: number;
  pointValueCents?: number;
  b2bSkipCustomers?: number;
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

export function monthlyReferralCapReached(
  referralsThisMonth: number,
  cap: number,
): boolean {
  return referralsThisMonth >= cap;
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

export function quoteReferralRewards(input: SpendRewardInput): RewardLine[] {
  if (input.fraudReason) return [];
  const pointValue = input.pointValueCents ?? officialPointValueCents;
  const commission = commissionCents(input.grossCents, input.commissionBps);
  let pool = commission - (input.subsidyCents ?? 0);
  if (pool < 0) pool = 0;
  const lines: RewardLine[] = [];
  const player = input.playerReferrer;
  if (
    player && attributionCovers(player, input.paidAt) && !input.payerCpfMissing
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
        });
        pool -= taken.cents;
      }
    }
  }
  const venue = input.venueReferrer;
  if (venue && attributionCovers(venue, input.paidAt)) {
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
          });
        }
      }
    } else if ((input.payerCustomerRank ?? 1) > (input.b2bSkipCustomers ?? 1)) {
      const cents = takeCents(input.grossCents, input.b2bBps ?? officialB2bBps, pool);
      if (cents > 0) {
        lines.push({
          program: "b2b",
          cents,
          points: 0,
          payee: "venue_credit",
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
};

export function quotePointSubsidy(input: {
  grossCents: number;
  commissionBps: number;
  requestedPoints: number;
  availablePoints: number;
  pointValueCents?: number;
}): PointSubsidyQuote {
  const pointValue = input.pointValueCents ?? officialPointValueCents;
  const commission = commissionCents(input.grossCents, input.commissionBps);
  const houseNet = input.grossCents - commission;
  const room = input.grossCents > 1 ? input.grossCents - 1 : 0;
  const maxSubsidy = Math.min(commission, room);
  const maxPoints = Math.floor(Math.max(maxSubsidy, 0) / pointValue);
  let points = input.requestedPoints;
  if (points < 0) points = 0;
  if (points > input.availablePoints) points = input.availablePoints;
  if (points > maxPoints) points = maxPoints;
  const subsidy = points * pointValue;
  const charged = input.grossCents - subsidy;
  return {
    grossCents: input.grossCents,
    chargedCents: charged,
    subsidyCents: subsidy,
    points,
    houseNetCents: houseNet,
    commissionCents: commission,
    splitPercent: subsidy === 0
      ? null
      : subsidizedHouseSplitPercent(houseNet, charged),
    maxPoints,
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
