type CommissionDb = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
};

/// Taxa vigente da casa: override, senão o padrão de platform_settings.
/// Quem cobra não inventa 10% no código.
export async function commissionBpsForVenue(
  admin: CommissionDb,
  venueId: string,
): Promise<number> {
  const { data, error } = await admin.rpc("commission_bps_for_venue", {
    p_venue_id: venueId,
  });
  const bps = typeof data === "number" ? data : Number(data);
  if (error || !Number.isInteger(bps) || bps < 0 || bps > 3000) {
    throw new Error("comissão indisponível");
  }
  return bps;
}
