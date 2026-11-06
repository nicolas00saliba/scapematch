import { assertEquals } from "jsr:@std/assert@1";
import { testPdfUrl, testXmlUrl } from "../_shared/fiscal_plan.ts";
import { isRemoteAsaasFile } from "./remote_asaas_file.ts";

Deno.test("arquivo remoto só em HTTPS no host da Asaas", () => {
  assertEquals(isRemoteAsaasFile("https://asaas.com/n.pdf"), true);
  assertEquals(isRemoteAsaasFile("https://files.asaas.com/n.pdf"), true);
  assertEquals(isRemoteAsaasFile("https://api.asaas.com/v3/n.pdf"), true);
  assertEquals(isRemoteAsaasFile("http://files.asaas.com/n.pdf"), false);
  assertEquals(isRemoteAsaasFile("https://notasaas.com/n.pdf"), false);
  assertEquals(isRemoteAsaasFile("https://asaas.com.evil.com/n.pdf"), false);
  assertEquals(isRemoteAsaasFile("https://evil.com/asaas.com"), false);
  assertEquals(isRemoteAsaasFile("https://evil.com/?x=asaas.com"), false);
  assertEquals(isRemoteAsaasFile("nota"), false);
  assertEquals(isRemoteAsaasFile(testPdfUrl("TESTE-1-S")), false);
  assertEquals(isRemoteAsaasFile(testXmlUrl("TESTE-1-C")), false);
});
