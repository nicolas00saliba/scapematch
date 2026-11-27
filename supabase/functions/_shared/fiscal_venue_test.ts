import { assertEquals } from "jsr:@std/assert@1";
import { fiscalVenueIdOf } from "./fiscal_venue.ts";

function adminWith(result: { data: unknown; error: unknown } | Error) {
  const seen: Record<string, unknown> = {};
  return {
    seen,
    from(table: string) {
      seen.table = table;
      const api = {
        select(columns: string) {
          seen.columns = columns;
          return api;
        },
        eq(column: string, value: unknown) {
          seen[column] = value;
          return api;
        },
        maybeSingle() {
          if (result instanceof Error) return Promise.reject(result);
          return Promise.resolve(result);
        },
      };
      return api;
    },
  };
}

Deno.test("cidade que usa a conta de outra emite pela dona da conta", async () => {
  const admin = adminWith({
    data: { pagbank_token_venue_id: "curitiba" },
    error: null,
  });
  assertEquals(await fiscalVenueIdOf(admin, "cascavel"), "curitiba");
  assertEquals(admin.seen.table, "venues");
  assertEquals(admin.seen.id, "cascavel");
});

Deno.test("cidade com conta própria emite por ela mesma", async () => {
  assertEquals(
    await fiscalVenueIdOf(
      adminWith({ data: { pagbank_token_venue_id: null }, error: null }),
      "curitiba",
    ),
    "curitiba",
  );
});

Deno.test("sem a coluna no banco ou em erro, a própria cidade", async () => {
  assertEquals(
    await fiscalVenueIdOf(
      adminWith({ data: null, error: { code: "42703" } }),
      "cascavel",
    ),
    "cascavel",
  );
  assertEquals(
    await fiscalVenueIdOf(adminWith(new Error("rede")), "cascavel"),
    "cascavel",
  );
});
