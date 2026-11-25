import { assert, assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider } from "./pagbank_provider.ts";
import { readAccountBalance } from "./pagbank_transfers.ts";

Deno.test("saldo da conta é sempre real decimal", async () => {
  assertEquals(readAccountBalance({ balance: 12 }).cents, 1200);
  assertEquals(readAccountBalance({ balance: 12.5 }).cents, 1250);
  assertEquals(readAccountBalance({ balance: -1.5 }).cents, -150);
  assertEquals(readAccountBalance({ balance: 12.5 }).exact, true);
  const odd = readAccountBalance({ balance: 12.555 });
  assertEquals(odd.exact, false);
  assertEquals(odd.cents, 1256);
  const shaped = readAccountBalance({ amount: { value: 10.5 } });
  assertEquals(shaped.cents, 1050);
  assertEquals(shaped.field, "amount");

  const lines: string[] = [];
  const original = console.error;
  console.error = (line?: unknown) => {
    lines.push(String(line ?? ""));
  };
  try {
    const provider = new PagBankProvider(
      "token",
      "https://api.pagseguro.com",
      () =>
        Promise.resolve(
          new Response(JSON.stringify({ balance: 12.555 }), { status: 200 }),
        ),
    );
    assertEquals(await provider.financeBalanceCents(), 1256);
    assert(lines.some((line) =>
      line.includes('"code":"balance_shape"') && !line.includes("12.555")
    ));
  } finally {
    console.error = original;
  }
});
