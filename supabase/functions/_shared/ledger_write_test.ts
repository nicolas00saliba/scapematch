import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  insertLedgerLine,
  ledgerConflictTarget,
  type LedgerLine,
} from "./ledger_write.ts";

const line: LedgerLine = {
  venue_id: "v-1",
  group_id: "g-1",
  user_id: "u-1",
  account: "platform",
  direction: "debit",
  kind: "commission_refund",
  amount_cents: 100,
  payment_charge_id: "ch-1",
};

Deno.test("23505 no upsert conta como duplicata e não insere de novo", async () => {
  let inserts = 0;
  const result = await insertLedgerLine({
    upsert: (_row, options) => {
      assertEquals(options, {
        onConflict: ledgerConflictTarget,
        ignoreDuplicates: true,
      });
      return Promise.resolve({
        error: { code: "23505", message: "duplicate key" },
      });
    },
    insert: () => {
      inserts += 1;
      return Promise.resolve({ error: null });
    },
  }, line);
  assertEquals(result, "duplicate");
  assertEquals(inserts, 0);
});

Deno.test("sem índice de conflito o insert trata 23505", async () => {
  const result = await insertLedgerLine({
    upsert: () =>
      Promise.resolve({
        error: {
          code: "42P10",
          message:
            "there is no unique or exclusion constraint matching the ON CONFLICT specification",
        },
      }),
    insert: () =>
      Promise.resolve({
        error: {
          code: "23505",
          message: "duplicate key value violates unique constraint",
        },
      }),
  }, line);
  assertEquals(result, "duplicate");
});

Deno.test("erro de escrita que não é 23505 é logado sem dados e lançado", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const email = "dono@casa.com";
  const secret = "chave-nao-pode-aparecer";
  try {
    await assertRejects(
      () =>
        insertLedgerLine({
          upsert: () =>
            Promise.resolve({
              error: {
                code: "23503",
                message: `fk ${email} ${secret} amount 100`,
              },
            }),
          insert: () => {
            throw new Error("não deveria inserir");
          },
        }, line),
      Error,
      "ledger_write_failed",
    );
  } finally {
    console.error = original;
  }
  assertEquals(logs.length, 1);
  const parsed = JSON.parse(logs[0]);
  assertEquals(parsed, { scope: "ledger", code: "23503" });
  assertEquals(logs[0].includes(email), false);
  assertEquals(logs[0].includes(secret), false);
  assertEquals(logs[0].includes("amount"), false);
});

Deno.test("insert de fallback também lança erro que não é 23505", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    await assertRejects(
      () =>
        insertLedgerLine({
          upsert: () =>
            Promise.resolve({
              error: { code: "42P10", message: "ON CONFLICT" },
            }),
          insert: () =>
            Promise.resolve({
              error: {
                code: "42501",
                message: "permission denied dono@casa.com",
              },
            }),
        }, line),
      Error,
      "ledger_write_failed",
    );
  } finally {
    console.error = original;
  }
  assertEquals(JSON.parse(logs[0]), { scope: "ledger", code: "42501" });
  assertEquals(logs[0].includes("dono@casa.com"), false);
});
