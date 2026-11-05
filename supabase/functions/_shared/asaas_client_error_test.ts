import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  asaasUnavailable,
  clientFailure,
  logAsaasFailure,
} from "./asaas_client_error.ts";

Deno.test("falha do Asaas vira código estável e o log não leva o corpo", () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const secret = "4111111111111111";
  const body = `cartão ${secret} cpf 04252011000110 token tok_segredo`;
  try {
    const error = new Error(`Asaas 400: ${body}`);
    const failure = clientFailure(error, "provision-venue-wallet");
    assertEquals(failure.status, 502);
    assertEquals(failure.error, asaasUnavailable);
    logAsaasFailure("settle-charges", error);
  } finally {
    console.error = original;
  }
  const joined = logs.join("\n");
  assert(joined.includes(asaasUnavailable));
  assert(joined.includes("provision-venue-wallet"));
  assertEquals(joined.includes(secret), false);
  assertEquals(joined.includes("04252011000110"), false);
  assertEquals(joined.includes("tok_segredo"), false);
  assertEquals(joined.includes("cartão"), false);
  assert(joined.includes('"status":"400"'));
});

Deno.test("as funções não devolvem error.message do Asaas", async () => {
  const files = [
    "../provision-venue-wallet/index.ts",
    "../create-charge/index.ts",
    "../settle-charges/index.ts",
    "../cancel-house-group/index.ts",
    "../configure-venue-fiscal/index.ts",
  ];
  for (const file of files) {
    const source = await Deno.readTextFile(new URL(file, import.meta.url));
    assert(source.includes("asaas_unavailable") || source.includes("clientFailure") || source.includes("safeClientText"), file);
    assertEquals(source.includes("error.message"), false, file);
    assertEquals(/console\s*\.\s*(log|error|info|debug)\s*\(\s*error\s*\)/.test(source), false, file);
  }
});
