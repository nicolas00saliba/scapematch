import { assert, assertEquals } from "jsr:@std/assert@1";
import { paymentChargePatch } from "./charge_patch.ts";

const now = "2026-11-05T18:00:00.000Z";

Deno.test("estorno preserva paid_at e grava refunded_at", () => {
  const fromPaid = paymentChargePatch({
    nextStatus: "refunded",
    previousStatus: "paid",
    now,
  });
  assertEquals(fromPaid.status, "refunded");
  assertEquals(fromPaid.refunded_at, now);
  assertEquals("paid_at" in fromPaid, false);

  const fromOther = paymentChargePatch({
    nextStatus: "refunded",
    previousStatus: "authorized",
    now,
  });
  assertEquals("paid_at" in fromOther, false);
  assertEquals(fromOther.refunded_at, now);
});

Deno.test("pagamento preenche paid_at e limpa refunded_at", () => {
  const patch = paymentChargePatch({
    nextStatus: "paid",
    previousStatus: "pending",
    now,
  });
  assertEquals(patch, {
    status: "paid",
    paid_at: now,
    refunded_at: null,
  });
});

Deno.test("o webhook monta o patch em vez de zerar paid_at", async () => {
  const source = await Deno.readTextFile(
    new URL("../asaas-webhook/index.ts", import.meta.url),
  );
  assert(source.includes("paymentChargePatch"));
  assertEquals(source.includes("paid_at: status"), false);
});
