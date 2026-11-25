import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  alertLowPjBalance,
  defaultLowBalanceAlertCents,
  shouldAlertLowBalance,
} from "./pj_balance.ts";

Deno.test("saldo abaixo do limite alerta e no limite não", () => {
  assertEquals(defaultLowBalanceAlertCents, 100_000);
  assertEquals(shouldAlertLowBalance(99_999, 100_000), true);
  assertEquals(shouldAlertLowBalance(100_000, 100_000), false);
  assertEquals(shouldAlertLowBalance(100_001, 100_000), false);
  assertEquals(shouldAlertLowBalance(0, 100_000), true);
  assertEquals(shouldAlertLowBalance(-1, 100_000), true);
  assertEquals(shouldAlertLowBalance(-150, 100_000), true);
});

Deno.test("o alerta de saldo sai sem o valor e não sai acima do limite", async () => {
  const lines: string[] = [];
  const fetches: string[] = [];
  const original = console.error;
  console.error = (line?: unknown) => {
    lines.push(String(line ?? ""));
  };
  try {
    const low = await alertLowPjBalance({
      env: { get: () => undefined },
      fetchFn: (url) => {
        fetches.push(url);
        return Promise.resolve({ ok: true });
      },
      availableCents: 99_999,
      limitCents: 100_000,
    });
    const enough = await alertLowPjBalance({
      env: { get: () => undefined },
      fetchFn: (url) => {
        fetches.push(url);
        return Promise.resolve({ ok: true });
      },
      availableCents: 100_000,
      limitCents: 100_000,
    });
    assertEquals(low, true);
    assertEquals(enough, false);
    assertEquals(fetches, []);
    assertEquals(lines.length, 1);
    assert(lines[0].includes('"scope":"pagbank-balance"'));
    assert(lines[0].includes('"code":"low_balance"'));
    assert(!lines[0].includes("99999"));
    assert(!lines[0].includes("100000"));
  } finally {
    console.error = original;
  }
});
