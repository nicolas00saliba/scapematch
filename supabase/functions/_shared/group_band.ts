/// Faixa do host. O mínimo confirma a cobrança. O máximo lota.
/// confirmed_at gruda: sair depois não desfaz a confirmação.

export type BandGroup = {
  cancelled_at?: string | null;
  confirmed_at?: string | null;
  closed_at?: string | null;
  closes_at?: string | null;
  total_spots: number;
  minimum_spots: number;
};

export type BandDecision = "release" | "capture" | "wait";

export function bandConfirmed(group: BandGroup, filled: number): boolean {
  if (group.cancelled_at) return false;
  if (group.confirmed_at || group.closed_at) return true;
  return filled >= Number(group.minimum_spots);
}

export function bandMissed(
  group: BandGroup,
  filled: number,
  now = Date.now(),
): boolean {
  if (group.cancelled_at) return false;
  if (bandConfirmed(group, filled)) return false;
  if (!group.closes_at) return false;
  return new Date(group.closes_at).getTime() <= now &&
    filled < Number(group.minimum_spots);
}

export function bandSettlement(
  group: BandGroup,
  filled: number,
  now = Date.now(),
): BandDecision {
  if (group.cancelled_at || bandMissed(group, filled, now)) return "release";
  if (bandConfirmed(group, filled)) return "capture";
  return "wait";
}
