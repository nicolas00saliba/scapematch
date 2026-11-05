import { assertEquals } from "jsr:@std/assert@1";
import { reverseLedger } from "./ledger.ts";

const charge = {
  id: "ch-1",
  group_id: "g-1",
  user_id: "u-1",
  venue_id: "v-1",
  amount_cents: 1000,
  commission_bps: 1000,
};

Deno.test("reverseLedger emite um débito por crédito e segue após 23505", async () => {
  const kinds: string[] = [];
  let upserts = 0;
  const admin = {
    from() {
      return {
        select() {
          const filters: Record<string, string> = {};
          const builder = {
            eq(column: string, value: string) {
              filters[column] = value;
              return builder;
            },
            limit() {
              return builder;
            },
            maybeSingle() {
              return Promise.resolve({ data: null });
            },
            then(
              resolve: (value: unknown) => unknown,
              reject?: (reason: unknown) => unknown,
            ) {
              const data = filters.direction === "credit"
                ? [
                  {
                    account: "platform",
                    kind: "commission",
                    amount_cents: 100,
                  },
                  { account: "house", kind: "house_net", amount_cents: 900 },
                ]
                : [];
              return Promise.resolve({ data }).then(resolve, reject);
            },
          };
          return builder;
        },
        upsert(
          row: { kind: string; direction: string },
          options: { onConflict: string; ignoreDuplicates: boolean },
        ) {
          upserts += 1;
          kinds.push(row.kind);
          assertEquals(row.direction, "debit");
          assertEquals(options.ignoreDuplicates, true);
          assertEquals(options.onConflict, "payment_charge_id,kind,direction");
          const error = upserts === 1
            ? { code: "23505", message: "duplicate key" }
            : null;
          return Promise.resolve({ error });
        },
        insert() {
          throw new Error("insert direto");
        },
      };
    },
  };
  await reverseLedger(admin, charge);
  assertEquals(kinds, ["commission_refund", "house_refund"]);
});

Deno.test("reverseLedger não relança estorno que já existe", async () => {
  const kinds: string[] = [];
  const admin = {
    from() {
      return {
        select() {
          const filters: Record<string, string> = {};
          const builder = {
            eq(column: string, value: string) {
              filters[column] = value;
              return builder;
            },
            limit() {
              return builder;
            },
            maybeSingle() {
              const exists = filters.kind === "commission_refund";
              return Promise.resolve({
                data: exists ? { id: "line-1" } : null,
              });
            },
            then(
              resolve: (value: unknown) => unknown,
              reject?: (reason: unknown) => unknown,
            ) {
              return Promise.resolve({
                data: [{
                  account: "platform",
                  kind: "commission",
                  amount_cents: 100,
                }],
              }).then(resolve, reject);
            },
          };
          return builder;
        },
        upsert(row: { kind: string }) {
          kinds.push(row.kind);
          return Promise.resolve({ error: null });
        },
        insert() {
          throw new Error("insert direto");
        },
      };
    },
  };
  await reverseLedger(admin, charge);
  assertEquals(kinds, []);
});
