import { assertEquals } from "jsr:@std/assert@1";
import { cronSecretTtlMs, resolveCronSecret } from "./cron_secret.ts";

Deno.test("a env tem prioridade e o vault não é lido", async () => {
  let reads = 0;
  const secret = await resolveCronSecret({
    envValue: "  da-env  ",
    vaultName: "venue_withdrawals_secret",
    readVault: () => {
      reads += 1;
      return Promise.resolve("do-vault");
    },
  });
  assertEquals(secret, "da-env");
  assertEquals(reads, 0);
});

Deno.test("sem env o vault entra no cache curto", async () => {
  let reads = 0;
  const cache = new Map<string, { value: string; until: number }>();
  const readVault = () => {
    reads += 1;
    return Promise.resolve("  do-vault  ");
  };
  const first = await resolveCronSecret({
    envValue: "",
    vaultName: "ledger_reconcile_secret",
    readVault,
    cache,
    now: 1_000,
  });
  const second = await resolveCronSecret({
    envValue: "   ",
    vaultName: "ledger_reconcile_secret",
    readVault,
    cache,
    now: 1_000 + cronSecretTtlMs - 1,
  });
  const third = await resolveCronSecret({
    envValue: undefined,
    vaultName: "ledger_reconcile_secret",
    readVault,
    cache,
    now: 1_000 + cronSecretTtlMs,
  });
  assertEquals(first, "do-vault");
  assertEquals(second, "do-vault");
  assertEquals(third, "do-vault");
  assertEquals(reads, 2);
});

Deno.test("vault vazio ou com erro vira segredo ausente", async () => {
  const empty = await resolveCronSecret({
    envValue: undefined,
    vaultName: "venue_withdrawals_secret",
    readVault: () => Promise.resolve(null),
  });
  const failed = await resolveCronSecret({
    envValue: undefined,
    vaultName: "venue_withdrawals_secret",
    readVault: () => Promise.reject(new Error("segredo-nao-logar")),
  });
  assertEquals(empty, "");
  assertEquals(failed, "");
});
