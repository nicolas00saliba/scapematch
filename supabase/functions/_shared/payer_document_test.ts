import { assertEquals } from "jsr:@std/assert@1";
import { pixTransactionId, syncPayerDocument } from "./payer_document.ts";

Deno.test("Pix sem documento no webhook fica não verificado e não libera", async () => {
  const writes: string[] = [];
  const status = await syncPayerDocument(admin(writes, null), undefined, {
    id: "ch-1",
    user_id: "user-1",
    billing_type: "PIX",
    provider_ref: "pay_1",
  }, { pixTransaction: null });
  assertEquals(status, "unverified");
  assertEquals(writes, ["unverified"]);
});

Deno.test("CPF mascarado da consulta Pix não libera a recompensa", async () => {
  const writes: string[] = [];
  const status = await syncPayerDocument(admin(writes, "52998224725"), {
    readPayment: () => Promise.resolve({ pixTransaction: "pix_1" }),
    getPixTransaction: () =>
      Promise.resolve({ payer: { cpfCnpj: "***.982.247-**" } }),
  }, charge(), { id: "pay_1", pixTransaction: "pix_1" });
  assertEquals(status, "unverified");
  assertEquals(writes, ["unverified"]);
});

Deno.test("CPF do pagador igual ao da conta libera", async () => {
  const writes: string[] = [];
  const status = await syncPayerDocument(admin(writes, "52998224725"), {
    readPayment: () => Promise.resolve({ pixTransaction: "pix_1" }),
    getPixTransaction: () =>
      Promise.resolve({ payer: { cpfCnpj: "529.982.247-25" } }),
  }, charge(), null);
  assertEquals(pixTransactionId({ pixTransaction: "pix_1" }), "pix_1");
  assertEquals(status, "matched");
});

Deno.test("CPF do pagador diferente barra e a reserva não depende disso", async () => {
  const writes: string[] = [];
  const status = await syncPayerDocument(admin(writes, "52998224725"), {
    readPayment: () => Promise.resolve({ pixTransaction: "pix_9" }),
    getPixTransaction: () =>
      Promise.resolve({ externalAccount: { cpfCnpj: "39053344705" } }),
  }, charge(), null);
  assertEquals(status, "mismatch");
  assertEquals(writes, ["mismatch"]);
});

Deno.test("consulta que falha não impede o pagamento e fica não verificada", async () => {
  const writes: string[] = [];
  const status = await syncPayerDocument(admin(writes, "52998224725"), {
    readPayment: () => Promise.reject(new Error("Asaas 503")),
    getPixTransaction: () => Promise.reject(new Error("Asaas 503")),
  }, charge(), null);
  assertEquals(status, "unverified");
});

function charge() {
  return {
    id: "ch-1",
    user_id: "user-1",
    billing_type: "PIX",
    provider_ref: "pay_1",
  };
}

function admin(writes: string[], cpf: string | null) {
  return {
    from(table: string) {
      return {
        select() {
          return {
            eq() {
              return {
                maybeSingle: () =>
                  Promise.resolve({
                    data: table === "profiles"
                      ? { cpf }
                      : { payer_document_status: null },
                    error: null,
                  }),
              };
            },
          };
        },
      };
    },
    rpc(_name: string, args: Record<string, unknown>) {
      writes.push(String(args.p_status));
      return Promise.resolve({ data: args.p_status, error: null });
    },
  };
}
