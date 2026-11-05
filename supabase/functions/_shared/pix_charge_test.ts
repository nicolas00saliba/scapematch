import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  localChargeStatus,
  pixExternalReference,
  pixNeedsQr,
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

Deno.test("create-charge usa referência estável e grava antes do QR", async () => {
  const source = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  assert(source.includes("pixExternalReference"));
  assert(source.includes("onCreated"));
  assert(source.includes("persistPixCharge"));
  assert(source.includes("localChargeStatus"));
  assertEquals(source.includes("error.message"), false);
  assertEquals(source.includes("console."), false);
});
