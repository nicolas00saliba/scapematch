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
    assertEquals(failure.body, { error: asaasUnavailable });
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
    "../tokenize-card/index.ts",
    "../invoice-document/index.ts",
    "../asaas-webhook/index.ts",
  ];
  for (const file of files) {
    const source = await Deno.readTextFile(new URL(file, import.meta.url));
    assert(source.includes("clientFailure"), file);
    assertEquals(source.includes("error.message"), false, file);
    assertEquals(
      /console\s*\.\s*(log|error|info|debug)\s*\(\s*error\s*\)/.test(source),
      false,
      file,
    );
  }
});

Deno.test("erro inesperado devolve internal_error e o log só tem tipo e ref", () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  const secret = "4111111111111111";
  const email = "ana@example.com";
  const raw = `cpf 04252011000110 ${email} token tok_segredo Authorization Bearer abc ${secret}`;
  try {
    const error = new TypeError(raw);
    const failure = clientFailure(error, "create-charge");
    assertEquals(failure.status, 500);
    assertEquals(failure.body.error, "internal_error");
    const ref = failure.body.ref ?? "";
    assert(/^[0-9a-f-]{36}$/.test(ref));
    assertEquals(logs.length, 1);
    const parsed = JSON.parse(logs[0]);
    assertEquals(Object.keys(parsed).sort(), ["code", "ref", "scope"]);
    assertEquals(parsed, { scope: "create-charge", code: "TypeError", ref });

    const named = new Error("segredo");
    named.name = email;
    const hidden = clientFailure(named, "tokenize-card");
    assertEquals(JSON.parse(logs[1]), {
      scope: "tokenize-card",
      code: "unknown",
      ref: hidden.body.ref,
    });
  } finally {
    console.error = original;
  }
  const joined = logs.join("\n");
  assertEquals(joined.includes(secret), false);
  assertEquals(joined.includes("04252011000110"), false);
  assertEquals(joined.includes(email), false);
  assertEquals(joined.includes("tok_segredo"), false);
  assertEquals(joined.includes("Bearer"), false);
  assertEquals(joined.includes("Authorization"), false);
});
