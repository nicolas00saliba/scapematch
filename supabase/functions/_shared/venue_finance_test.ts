import { assertEquals } from "jsr:@std/assert@1";
import {
  financeBlockedMessage,
  paymentBlock,
  walletBlockedMessage,
} from "./venue_finance.ts";

Deno.test("pagamento exige subconta e conta bancária", () => {
  assertEquals(
    paymentBlock({
      status: "approved",
      walletId: null,
      hasBankAccount: true,
    }),
    walletBlockedMessage,
  );
  assertEquals(
    paymentBlock({
      status: "approved",
      walletId: "wal_casa",
      hasBankAccount: false,
    }),
    financeBlockedMessage,
  );
  assertEquals(
    paymentBlock({
      status: "pending",
      walletId: "wal_casa",
      hasBankAccount: true,
    }),
    walletBlockedMessage,
  );
  assertEquals(
    paymentBlock({
      status: "approved",
      walletId: " wal_casa ",
      hasBankAccount: true,
    }),
    null,
  );
});
