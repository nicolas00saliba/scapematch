import { assertEquals } from "jsr:@std/assert@1";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";

Deno.test("a conciliação não chama provedor", async () => {
  const result = await reconcilePayments({
    rpc() {
      throw new Error("nao devia");
    },
  });
  assertEquals(result, { resolved: 0, pending: 0 });
});
