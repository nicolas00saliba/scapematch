import { assert, assertEquals } from "jsr:@std/assert@1";
import { commissionBpsForVenue } from "./commission_rate.ts";

Deno.test("a cobrança lê a taxa configurada e não o 10% fixo", async () => {
  const calls: string[] = [];
  const bps = await commissionBpsForVenue({
    rpc(name, args) {
      calls.push(`${name}:${args.p_venue_id}`);
      return Promise.resolve({ data: 800, error: null });
    },
  }, "venue-1");
  assertEquals(bps, 800);
  assertEquals(calls, ["commission_bps_for_venue:venue-1"]);

  const charge = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  assert(charge.includes("commissionBpsForVenue"));
  assertEquals(charge.includes("?? 1000"), false);
  const settle = await Deno.readTextFile(
    new URL("../settle-charges/index.ts", import.meta.url),
  );
  assert(settle.includes("commission_bps"));
  assertEquals(settle.includes("?? 1000"), false);
});
