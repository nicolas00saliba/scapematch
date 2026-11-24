import { assertEquals } from "jsr:@std/assert@1";
import {
  paymentBlock,
  walletBlockedMessage,
} from "./venue_finance.ts";

Deno.test("pagamento exige conta PagBank e não exige banco de saque", () => {
  assertEquals(
    paymentBlock({
      status: "approved",
      walletId: null,
    }),
    walletBlockedMessage,
  );
  assertEquals(
    paymentBlock({
      status: "pending",
      walletId: "wal_casa",
    }),
    walletBlockedMessage,
  );
  assertEquals(
    paymentBlock({
      status: "approved",
      walletId: " wal_casa ",
    }),
    null,
  );
});
