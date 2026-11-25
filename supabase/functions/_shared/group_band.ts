/// Faixa do host. O mínimo confirma a cobrança. O máximo lota.
/// confirmed_at gruda: sair depois não desfaz a confirmação.
/// Prazo vencido sem confirmed_at não confirma, mesmo com o mínimo cheio.

export type BandGroup = {
  cancelled_at?: string | null;
  confirmed_at?: string | null;
  closed_at?: string | null;
  closes_at?: string | null;
  total_spots: number;
  minimum_spots: number;
};

export type BandDecision = "release" | "capture" | "wait";

function deadlinePassed(group: BandGroup, now: number): boolean {
  if (!group.closes_at) return false;
  return new Date(group.closes_at).getTime() <= now;
}

export function bandConfirmed(
  group: BandGroup,
  filled: number,
  now = Date.now(),
): boolean {
  if (group.cancelled_at) return false;
  if (group.confirmed_at || group.closed_at) return true;
  if (deadlinePassed(group, now)) return false;
  return filled >= Number(group.minimum_spots);
}

/// Prazo passou e o grupo nunca confirmou. O número de pessoas não reabre.
export function bandMissed(
  group: BandGroup,
  filled: number,
  now = Date.now(),
): boolean {
  if (group.cancelled_at) return false;
  if (bandConfirmed(group, filled, now)) return false;
  return deadlinePassed(group, now);
}

/// O integrante que completou o mínimo entrou até o closes_at.
/// Sem essa prova, prazo vencido continua sem confirmação.
export function minimumReachedOnTime(
  closesAt: string | null | undefined,
  minimumSpots: number,
  joinedAt: readonly string[],
): boolean {
  if (!closesAt || minimumSpots <= 0) return false;
  const deadline = Date.parse(closesAt);
  if (!Number.isFinite(deadline)) return false;
  const times = joinedAt
    .map((item) => Date.parse(item))
    .filter((item) => Number.isFinite(item))
    .sort((left, right) => left - right);
  const nth = times[minimumSpots - 1];
  return nth !== undefined && nth <= deadline;
}

export function joinedAtFromRows(data: unknown): string[] | null {
  if (!Array.isArray(data)) return null;
  const times: string[] = [];
  for (const row of data) {
    if (!row || typeof row !== "object") continue;
    const value = (row as { joined_at?: unknown }).joined_at;
    if (typeof value === "string") times.push(value);
  }
  return times;
}

export function bandSettlement(
  group: BandGroup,
  filled: number,
  now = Date.now(),
): BandDecision {
  if (group.cancelled_at || bandMissed(group, filled, now)) return "release";
  if (bandConfirmed(group, filled, now)) return "capture";
  return "wait";
}
