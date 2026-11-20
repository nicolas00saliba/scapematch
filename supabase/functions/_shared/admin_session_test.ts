import { assertEquals } from "jsr:@std/assert@1";
import { adminWithMfa, sessionAal } from "./admin_session.ts";

function jwt(claims: Record<string, unknown>): string {
  const body = btoa(JSON.stringify(claims)).replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ).replace(/=+$/, "");
  return `Bearer h.${body}.s`;
}

Deno.test("admin com aal2 passa", () => {
  assertEquals(adminWithMfa(true, jwt({ sub: "a", aal: "aal2" })), true);
});

Deno.test("admin só com senha (aal1) não passa", () => {
  assertEquals(adminWithMfa(true, jwt({ sub: "a", aal: "aal1" })), false);
});

Deno.test("quem não está em admins não vira admin com aal2", () => {
  assertEquals(adminWithMfa(false, jwt({ sub: "a", aal: "aal2" })), false);
});

Deno.test("token ausente ou quebrado não tem aal", () => {
  assertEquals(sessionAal(""), "");
  assertEquals(sessionAal("Bearer lixo"), "");
  assertEquals(sessionAal("Bearer a.%%%.c"), "");
  assertEquals(adminWithMfa(true, "Bearer a.%%%.c"), false);
});
