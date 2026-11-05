import { assertEquals } from "jsr:@std/assert@1";
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
