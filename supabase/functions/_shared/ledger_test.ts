import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { creditLedger, reverseLedger } from "./ledger.ts";

const charge = {
  id: "ch-1",
  group_id: "g-1",
  user_id: "u-1",
  venue_id: "v-1",
  amount_cents: 1000,
  commission_bps: 1000,
};

Deno.test("reverseLedger pede refunded na mesma transação", async () => {
  let name = "";
  let args: unknown;
  await reverseLedger({
    rpc(fn, payload) {
      name = fn;
      args = payload;
      return Promise.resolve({
        data: {
          applied: true,
          status: "refunded",
          paid_at: "2026-11-05T12:00:00.000Z",
          refunded_at: "2026-11-05T18:00:00.000Z",
        },
        error: null,
      });
    },
  }, charge);
  assertEquals(name, "apply_payment_transition");
  assertEquals(args, {
    p_charge_id: "ch-1",
    p_next_status: "refunded",
    p_credit: false,
  });
});

Deno.test("erro de escrita do ledger é lançado sem a mensagem do banco", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const email = "dono@casa.com";
  try {
    await assertRejects(
      () =>
        creditLedger({
          rpc() {
            return Promise.resolve({
              data: null,
              error: { code: "23503", message: `fk ${email}` },
            });
          },
        }, charge),
      Error,
      "ledger_write_failed",
    );
  } finally {
    console.error = original;
  }
  assertEquals(JSON.parse(logs[0]), { scope: "ledger", code: "23503" });
  assertEquals(logs[0].includes(email), false);
});
