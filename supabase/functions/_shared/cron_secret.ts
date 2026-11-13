// A env ganha da leitura do Vault. O valor não entra em log nem em erro.

export const cronSecretTtlMs = 60_000;

export type SecretCache = Map<string, { value: string; until: number }>;

export function createSecretCache(): SecretCache {
  return new Map();
}

export async function resolveCronSecret(input: {
  envValue: string | undefined;
  vaultName: string;
  readVault?: () => Promise<unknown>;
  cache?: SecretCache;
  now?: number;
}): Promise<string> {
  const fromEnv = (input.envValue ?? "").trim();
  if (fromEnv !== "") return fromEnv;
  const now = input.now ?? Date.now();
  const cached = input.cache?.get(input.vaultName);
  if (cached && cached.until > now && cached.value !== "") return cached.value;
  if (!input.readVault) return "";
  let value = "";
  try {
    value = secretText(await input.readVault());
  } catch {
    return "";
  }
  if (value !== "" && input.cache) {
    input.cache.set(input.vaultName, {
      value,
      until: now + cronSecretTtlMs,
    });
  }
  return value;
}

function secretText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
