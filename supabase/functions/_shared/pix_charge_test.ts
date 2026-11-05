import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  cardSwitchDecision,
  localChargeStatus,
  lostAttemptCompensation,
  pixExternalReference,
  pixLeaseExpired,
  pixMatchesCharge,
  pixNeedsQr,
  pixReservationAction,
  releaseReservationOnError,
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
  assert(source.includes("claim_expired_pix_reservation"));
  assert(source.includes("release_pix_reservation"));
  assert(source.includes("cancelPaymentConfirmed"));
  assert(source.includes("clear_pix_provider_ref"));
  assert(source.includes("record_orphan_payment"));
  assert(source.includes("findByExternalReference"));
  assert(source.includes("p_attempt_id"));
  assertEquals(source.includes(".update(row)"), false);
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
      leaseExpired: true,
    }),
    "reuse",
  );
  assertEquals(
    pixReservationAction({
      inserted: false,
      providerRef: null,
      billingType: "PIX",
      leaseExpired: false,
    }),
    "busy",
  );
  assertEquals(
    pixReservationAction({
      inserted: false,
      providerRef: null,
      billingType: "PIX",
      leaseExpired: true,
    }),
    "reclaim",
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

Deno.test("lease de 2 minutos e 4xx liberam a reserva presa", () => {
  const now = Date.parse("2026-11-05T18:00:00.000Z");
  assertEquals(
    pixLeaseExpired("2026-11-05T17:57:00.000Z", now),
    true,
  );
  assertEquals(
    pixLeaseExpired("2026-11-05T17:59:30.000Z", now),
    false,
  );
  assertEquals(pixLeaseExpired(null, now), true);
  assertEquals(
    releaseReservationOnError(new Error("Asaas 400: recusado")),
    true,
  );
  assertEquals(releaseReservationOnError(new Error("Asaas 422: x")), true);
  assertEquals(releaseReservationOnError(new Error("Asaas 500: fora")), false);
  assertEquals(
    releaseReservationOnError(new Error("Asaas 502: pix_qr_unavailable")),
    false,
  );
  assertEquals(releaseReservationOnError(new TypeError("timeout")), false);
  assertEquals(lostAttemptCompensation("CONFIRMED"), "refund");
  assertEquals(lostAttemptCompensation("RECEIVED"), "refund");
  assertEquals(lostAttemptCompensation("AUTHORIZED"), "cancel");
  assertEquals(lostAttemptCompensation("REFUNDED"), "none");
});

Deno.test("Pix pendente cancela antes do cartão; Pix pago recusa", () => {
  assertEquals(
    cardSwitchDecision({
      billingType: "PIX",
      status: "pending",
      providerRef: "pay_1",
    }),
    "cancel_pix",
  );
  assertEquals(
    cardSwitchDecision({
      billingType: "PIX",
      status: "paid",
      providerRef: "pay_1",
    }),
    "refuse",
  );
  assertEquals(
    cardSwitchDecision({
      billingType: "PIX",
      status: "creating",
      providerRef: null,
      leaseExpired: false,
    }),
    "refuse",
  );
  assertEquals(
    cardSwitchDecision({
      billingType: "PIX",
      status: "creating",
      providerRef: null,
      leaseExpired: true,
    }),
    "drop_lease",
  );
  assertEquals(cardSwitchDecision(null), "proceed");
  assertEquals(
    cardSwitchDecision({
      billingType: "CREDIT_CARD",
      status: "creating",
      providerRef: null,
      leaseExpired: false,
    }),
    "refuse",
  );
  assertEquals(
    cardSwitchDecision({
      billingType: "CREDIT_CARD",
      status: "creating",
      providerRef: null,
      leaseExpired: true,
    }),
    "drop_lease",
  );
});
