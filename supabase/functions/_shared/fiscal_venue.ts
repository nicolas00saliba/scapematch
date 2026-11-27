/// Qual casa assina a nota fiscal de uma cidade.

export const sharedFiscalMessage =
  "Esta cidade recebe pela conta PagBank de outra cidade da casa, e a nota sai pelo CNPJ dessa conta. Configure a nota fiscal na cidade dona da conta.";

/// Casa cujo CNPJ e dados fiscais assinam a nota: a dona da conta PagBank
/// que recebe. Cidade que usa a conta de outra (`pagbank_token_venue_id`)
/// devolve a outra. Sem a coluna no banco ou em erro, a própria cidade.
export async function fiscalVenueIdOf(
  // deno-lint-ignore no-explicit-any
  admin: any,
  venueId: string,
): Promise<string> {
  try {
    const { data, error } = await admin
      .from("venues")
      .select("pagbank_token_venue_id")
      .eq("id", venueId)
      .maybeSingle();
    if (error) return venueId;
    const pointer = (data as { pagbank_token_venue_id?: unknown } | null)
      ?.pagbank_token_venue_id;
    return typeof pointer === "string" && pointer.length > 0
      ? pointer
      : venueId;
  } catch {
    return venueId;
  }
}
