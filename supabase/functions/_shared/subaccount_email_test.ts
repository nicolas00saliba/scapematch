import { assert, assertEquals } from "jsr:@std/assert@1";
import { logAsaasFailure } from "./asaas_client_error.ts";
import {
  fallbackSubaccountDomain,
  nextSubaccountEmail,
  subaccountEmailPlan,
  venueAliasEmail,
} from "./subaccount_email.ts";

const venueId = "11111111-2222-4333-8444-555555555555";

Deno.test("sem e-mail da casa o alias é determinístico e ignora o login", () => {
  const env = { get: () => undefined };
  const plan = subaccountEmailPlan({ id: venueId }, env);
  const again = subaccountEmailPlan({ id: venueId }, env);
  assertEquals(plan.primary, plan.alias);
  assertEquals(plan.alias, again.alias);
  assertEquals(
    plan.alias,
    `parceiros+${venueId}@${fallbackSubaccountDomain}`,
  );
  assertEquals(plan.alias.includes("dono@"), false);
});

Deno.test("e-mail de contato ou fiscal da casa ganha do alias", () => {
  const env = { get: () => undefined };
  const contact = subaccountEmailPlan({
    id: venueId,
    contact_email: "Casa@Escape.test",
  }, env);
  assertEquals(contact.primary, "casa@escape.test");
  assert(contact.alias.startsWith("parceiros+"));
  const fiscal = subaccountEmailPlan({
    id: venueId,
    fiscal_email: "fiscal@casa.test",
  }, env);
  assertEquals(fiscal.primary, "fiscal@casa.test");
});

Deno.test("domínio do alias vem do env e o inválido cai no fallback", () => {
  const logs: string[] = [];
  const original = console.warn;
  console.warn = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    const custom = subaccountEmailPlan({ id: venueId }, {
      get: (name) =>
        name === "ASAAS_SUBACCOUNT_EMAIL_DOMAIN"
          ? "mail.escapematch.com.br"
          : undefined,
    });
    assertEquals(
      custom.alias,
      venueAliasEmail(venueId, "mail.escapematch.com.br"),
    );
    assertEquals(logs.length, 0);
    const broken = subaccountEmailPlan({ id: venueId }, {
      get: () => "não é domínio",
    });
    assertEquals(broken.alias.endsWith(`@${fallbackSubaccountDomain}`), true);
    assertEquals(logs.length, 1);
    const parsed = JSON.parse(logs[0]);
    assertEquals(parsed.scope, "subaccount_email");
    assertEquals(parsed.code, "invalid_email_domain");
    assertEquals(parsed.fallback, "escapematch.com.br");
    assertEquals(logs[0].includes("scapematch.app"), false);
    assertEquals(logs[0].includes("não é domínio"), false);
  } finally {
    console.warn = original;
  }
});

Deno.test("sem ASAAS_SUBACCOUNT_EMAIL_DOMAIN avisa e usa escapematch.com.br", () => {
  const logs: string[] = [];
  const original = console.warn;
  console.warn = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    const missing = subaccountEmailPlan({ id: venueId }, {
      get: () => undefined,
    });
    const blank = subaccountEmailPlan({ id: venueId }, {
      get: () => "  ",
    });
    assertEquals(
      missing.alias,
      `parceiros+${venueId}@escapematch.com.br`,
    );
    assertEquals(blank.alias, missing.alias);
    assertEquals(fallbackSubaccountDomain, "escapematch.com.br");
    assertEquals(logs.length, 2);
    for (const line of logs) {
      const parsed = JSON.parse(line);
      assertEquals(parsed.scope, "subaccount_email");
      assertEquals(parsed.code, "missing_email_domain");
      assertEquals(parsed.fallback, "escapematch.com.br");
      assertEquals(line.includes("scapematch.app"), false);
    }
  } finally {
    console.warn = original;
  }
});

Deno.test("e-mail duplicado no Asaas pede o alias; outro 400 não", () => {
  const alias = venueAliasEmail(venueId, fallbackSubaccountDomain);
  const duplicate = new Error(
    `Asaas 400: ${
      JSON.stringify({
        errors: [{
          code: "invalid_object",
          description: "Já existe uma conta com o e-mail dono@casa.com",
        }],
      })
    }`,
  );
  assertEquals(
    nextSubaccountEmail("dono@casa.com", alias, duplicate),
    alias,
  );
  assertEquals(nextSubaccountEmail(alias, alias, duplicate), null);
  const other = new Error(
    `Asaas 400: ${
      JSON.stringify({
        errors: [{ code: "invalid_object", description: "CEP inválido" }],
      })
    }`,
  );
  assertEquals(nextSubaccountEmail("dono@casa.com", alias, other), null);
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    logAsaasFailure("provision-venue-wallet", duplicate);
  } finally {
    console.error = original;
  }
  const parsed = JSON.parse(logs[0]);
  assertEquals(parsed.errors, [{ code: "invalid_object" }]);
  assertEquals(logs[0].includes("dono@casa.com"), false);
  assertEquals(logs[0].includes("Já existe"), false);
});

Deno.test("provision-venue-wallet não usa o e-mail de login", async () => {
  const source = await Deno.readTextFile(
    new URL("../provision-venue-wallet/index.ts", import.meta.url),
  );
  assert(source.includes("subaccountEmailPlan"));
  assert(source.includes("nextSubaccountEmail"));
  assertEquals(source.includes("owner.data.user?.email"), false);
  assertEquals(source.includes("error.message"), false);
  assertEquals(source.includes("console."), false);
});
