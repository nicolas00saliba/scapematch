import { assertEquals } from "jsr:@std/assert@1";
import { testPdfUrl, testXmlUrl } from "../_shared/fiscal_plan.ts";
import { isRemoteInvoiceFile } from "./remote_invoice_file.ts";

Deno.test("arquivo remoto só em HTTPS no host da PagBank", () => {
  assertEquals(isRemoteInvoiceFile("https://pagbank.com/n.pdf"), true);
  assertEquals(isRemoteInvoiceFile("https://files.pagbank.com/n.pdf"), true);
  assertEquals(isRemoteInvoiceFile("https://api.pagseguro.com/n.pdf"), true);
  assertEquals(isRemoteInvoiceFile("http://files.pagbank.com/n.pdf"), false);
  assertEquals(isRemoteInvoiceFile("https://notpagbank.com/n.pdf"), false);
  assertEquals(isRemoteInvoiceFile("https://pagbank.com.evil.com/n.pdf"), false);
  assertEquals(isRemoteInvoiceFile("https://evil.com/pagbank.com"), false);
  assertEquals(isRemoteInvoiceFile("https://evil.com/?x=pagbank.com"), false);
  assertEquals(isRemoteInvoiceFile("nota"), false);
  assertEquals(isRemoteInvoiceFile(testPdfUrl("TESTE-1-S")), false);
  assertEquals(isRemoteInvoiceFile(testXmlUrl("TESTE-1-C")), false);
});
