import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  localChargeStatus,
  pixExternalReference,
  pixMatchesCharge,
  pixNeedsQr,
  pixReservationAction,
} from "./pix_charge.ts";

Deno.test("a referência do Pix não muda com a chave do cliente", () => {
  const first = pixExternalReference("group-1", "user-1");
  const second = pixExternalReference("group-1", "user-1");
  assertEquals(first, "pix:group-1:user-1");
  assertEquals(second, first);
  assertEquals(first.includes("pay-"), false);
  assertThrows(() => pixExternalReference("", "user-1"));
});

Deno.test("Pix pendente sem QR pede nova busca e não outra cobrança", () => {
  assertEquals(
    pixNeedsQr({
      status: "pending",
      billing_type: "PIX",
      provider_ref: "pay_1",
      qr_code: null,
    }),
    true,
  );
  assertEquals(
    pixNeedsQr({
      status: "pending",
      billing_type: "PIX",
      provider_ref: "pay_1",
      qr_code: "000201",
    }),
    false,
  );
  assertEquals(
    pixNeedsQr({
      status: "refunded",
      billing_type: "PIX",
      provider_ref: "pay_1",
      qr_code: null,
    }),
    false,
  );
  assertEquals(
    pixNeedsQr({
      status: "paid",
      billing_type: "PIX",
      provider_ref: "pay_1",
      qr_code: null,
    }),
    false,
  );
});

Deno.test("RECEIVED e CONFIRMED viram pago; pendente continua pendente", () => {
  assertEquals(localChargeStatus("RECEIVED"), "paid");
  assertEquals(localChargeStatus("confirmed"), "paid");
  assertEquals(localChargeStatus("PENDING"), "pending");
  assertEquals(localChargeStatus("OVERDUE"), "pending");
});

Deno.test("create-charge reserva o Pix e não troca provider_ref", async () => {
  const source = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  assert(source.includes("pixExternalReference"));
  assert(source.includes("onCreated"));
  assert(source.includes("reserve_pix_charge"));
  assert(source.includes("attach_pix_provider"));
  assert(source.includes("pixReservationAction"));
  assert(source.includes("pixMatchesCharge"));
  assertEquals(source.includes("persistPixCharge"), false);
  assertEquals(source.includes("error.message"), false);
  assertEquals(source.includes("console."), false);
});

const expectedPix = {
  customer: "cus_1",
  valueCents: 12000,
  walletId: "wal_house",
  percentualValue: 90,
};

Deno.test("reuso do Pix exige customer, valor, split e status", () => {
  const remote = {
    customer: "cus_1",
    value: 120,
    status: "RECEIVED",
    billingType: "PIX",
    split: [{ walletId: "wal_house", percentualValue: 90 }],
  };
  assertEquals(pixMatchesCharge(remote, expectedPix), true);
  assertEquals(
    pixMatchesCharge({ ...remote, customer: "cus_2" }, expectedPix),
    false,
  );
  assertEquals(pixMatchesCharge({ ...remote, value: 10 }, expectedPix), false);
  assertEquals(
    pixMatchesCharge({ ...remote, status: "REFUNDED" }, expectedPix),
    false,
  );
  assertEquals(localChargeStatus("RECEIVED"), "paid");
});

Deno.test("reserva não cria de novo nem sobrescreve provider_ref", () => {
  assertEquals(
    pixReservationAction({
      inserted: true,
      providerRef: null,
      billingType: "PIX",
    }),
    "create",
  );
  assertEquals(
    pixReservationAction({
      inserted: false,
      providerRef: "pay_1",
      billingType: "PIX",
    }),
    "reuse",
  );
  assertEquals(
    pixReservationAction({
      inserted: false,
      providerRef: null,
      billingType: "PIX",
    }),
    "busy",
  );
  assertEquals(
    pixReservationAction({
      inserted: false,
      providerRef: "pay_card",
      billingType: "CREDIT_CARD",
    }),
    "refuse",
  );
});
