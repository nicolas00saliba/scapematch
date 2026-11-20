import { assertEquals } from "jsr:@std/assert@1";
import { invoiceEmissionEnabled, issuePaidInvoices } from "./issue_invoices.ts";

Deno.test("a NFS-e não chama provedor", async () => {
  assertEquals(invoiceEmissionEnabled("on"), false);
  let called = false;
  await issuePaidInvoices({
    from() {
      called = true;
      return {};
    },
  }, { id: "c1" });
  assertEquals(called, false);
});
