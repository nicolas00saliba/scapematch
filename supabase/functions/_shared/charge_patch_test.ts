import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  chargeTransitions,
  confirmedChargeStatus,
  memberPaymentForStatus,
  paymentChargePatch,
  paymentRefForRead,
  paymentTransition,
  requestedChargeStatus,
} from "./charge_patch.ts";

const now = "2026-11-05T18:00:00.000Z";
const earlier = "2026-11-05T12:00:00.000Z";

Deno.test("RECEIVED depois de REFUNDED não volta para paid", () => {
  assertEquals(paymentTransition("refunded", "paid"), "refunded");
  const patch = paymentChargePatch({
    nextStatus: "paid",
    previousStatus: "refunded",
    now,
    paidAt: earlier,
    refundedAt: earlier,
  });
  assertEquals(patch.status, "refunded");
  assertEquals(patch.paid_at, undefined);
  assertEquals(patch.refunded_at, earlier);
});

Deno.test("replay de pago preserva o primeiro paid_at", () => {
  const patch = paymentChargePatch({
    nextStatus: "paid",
    previousStatus: "paid",
    now,
    paidAt: earlier,
  });
  assertEquals(patch.status, "paid");
  assertEquals(patch.paid_at, earlier);
  assertEquals(patch.refunded_at, undefined);
});

Deno.test("estorno preserva paid_at e grava refunded_at uma vez", () => {
  const fromPaid = paymentChargePatch({
    nextStatus: "refunded",
    previousStatus: "paid",
    now,
    paidAt: earlier,
  });
  assertEquals(fromPaid.status, "refunded");
  assertEquals(fromPaid.refunded_at, now);
  assertEquals(fromPaid.paid_at, undefined);

  const again = paymentChargePatch({
    nextStatus: "refunded",
    previousStatus: "refunded",
    now,
    paidAt: earlier,
    refundedAt: earlier,
  });
  assertEquals(again.refunded_at, earlier);
  assertEquals(again.paid_at, undefined);
});

Deno.test("pending pode ir para paid e cancelled não sai", () => {
  assertEquals(paymentTransition("pending", "paid"), "paid");
  assertEquals(paymentTransition("cancelled", "paid"), "cancelled");
  assertEquals(paymentTransition("paid", "pending"), "paid");
  assertEquals(confirmedChargeStatus("RECEIVED"), "paid");
  assertEquals(confirmedChargeStatus("REFUNDED"), "refunded");
  assertEquals(requestedChargeStatus("PAYMENT_RECEIVED", "RECEIVED"), "paid");
});

Deno.test("estorno deixa o membro released e o GET usa o id do banco", () => {
  const status = paymentTransition("refunded", "paid");
  assertEquals(memberPaymentForStatus(status), {
    payment_status: "released",
    refund_status: "refunded",
  });
  assertEquals(paymentRefForRead("pay_db", "pay_payload"), "pay_db");
  assertEquals(paymentRefForRead(null, "pay_payload"), null);
  assertEquals(paymentRefForRead("  ", "pay_payload"), null);
});

Deno.test("comissão alta cabe em bigint antes da divisão", async () => {
  const amountCents = 800_000;
  const bps = 3000;
  assert(amountCents * bps > 2_147_483_647);
  assertEquals(Math.floor((amountCents * bps + 5000) / 10000), 240_000);
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261105210000_ledger_charge_kind_direction.sql",
      import.meta.url,
    ),
  );
  assert(sql.includes("amount_cents::bigint * v_charge.commission_bps"));
  assert(sql.includes("on conflict (payment_charge_id, kind, direction)"));
  assertEquals(sql.includes("on conflict do nothing"), false);
});

Deno.test("a migração trava a cobrança e falha se houver duplicata", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261105210000_ledger_charge_kind_direction.sql",
      import.meta.url,
    ),
  );
  assert(sql.includes("for update"));
  assert(sql.includes("coalesce(paid_at"));
  assert(sql.includes("coalesce(refunded_at"));
  assert(sql.includes("raise exception"));
  assert(sql.includes("provider_ref is null"));
  assert(sql.includes("on conflict (group_id, user_id) do nothing"));
  assert(sql.includes("set search_path = ''"));
  assert(sql.includes("to service_role"));
  assertEquals(sql.includes("delete from public.ledger_entries"), false);
  for (const [from, targets] of Object.entries(chargeTransitions)) {
    assert(sql.includes(`p_from = '${from}'`), from);
    for (const target of targets) {
      assert(sql.includes(`'${target}'`), `${from}->${target}`);
    }
  }
});

Deno.test("o webhook confirma no Asaas e usa a transição", async () => {
  const source = await Deno.readTextFile(
    new URL("../asaas-webhook/index.ts", import.meta.url),
  );
  assert(source.includes("getPayment"));
  assert(source.includes("paymentRefForRead"));
  assert(source.includes("applyPaymentTransition"));
  assert(source.includes("confirmedChargeStatus"));
  assertEquals(source.includes("paymentChargePatch"), false);
  assertEquals(source.includes("payment_status"), false);
  const release = await Deno.readTextFile(
    new URL("./release_charges.ts", import.meta.url),
  );
  const settle = await Deno.readTextFile(
    new URL("./settle_group.ts", import.meta.url),
  );
  assertEquals(release.includes("payment_status"), false);
  assertEquals(settle.includes("payment_status"), false);
  assert(release.includes("applyPaymentTransition"));
  assert(settle.includes("applyPaymentTransition"));
  assertEquals(source.includes("error.message"), false);
});
