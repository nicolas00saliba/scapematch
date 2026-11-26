import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  bindingAlertCode,
  bindingBlocksMoney,
  conflictBody,
  conflictFromRpc,
  ownerMayDisconnect,
  parseBinding,
} from "./pagbank_binding.ts";

Deno.test("PB409 vira conflito 409 com mensagem clara", () => {
  const exists = conflictFromRpc({
    code: "PB409",
    message: "pagbank_account_exists",
  });
  assertEquals(exists?.code, "pagbank_account_exists");
  assert(conflictBody(exists!).message.includes("desconecte"));
  const busy = conflictFromRpc({ message: "pagbank_in_flight" });
  assertEquals(busy?.code, "pagbank_in_flight");
  assert(conflictBody(busy!).message.includes("a caminho"));
  assertEquals(
    conflictFromRpc({ message: "pagbank_account_mismatch" })?.code,
    "pagbank_account_mismatch",
  );
  assertEquals(conflictFromRpc({ code: "PB409", message: "x" })?.code,
    "pagbank_account_exists");
  assertEquals(conflictFromRpc({ code: "23505", message: "dup" }), null);
  assertEquals(conflictFromRpc(null), null);
});

Deno.test("a conta mascarada não vai na mensagem de conflito", () => {
  const body = conflictBody(
    conflictFromRpc({ message: "pagbank_account_exists" })!,
  );
  assertEquals(/ACCO_|\.\.\.\w{4}/.test(JSON.stringify(body)), false);
});

Deno.test("o binding ambíguo ou ilegível bloqueia o dinheiro", () => {
  for (const raw of [
    { state: "ambiguous", reason: "tokens_other_account" },
    { state: "ambiguous", reason: "tokens_without_account" },
    null,
    "ok",
    { state: "outro" },
    [],
  ]) {
    assert(bindingBlocksMoney(parseBinding(raw)), JSON.stringify(raw));
  }
  for (const state of ["none", "ok", "unverified"]) {
    assertEquals(bindingBlocksMoney(parseBinding({ state })), false);
  }
  assertEquals(
    bindingBlocksMoney(parseBinding([{ state: "ok" }])),
    false,
  );
});

Deno.test("o alerta separa conta ambígua, token sem conta e ilegível", () => {
  assertEquals(
    bindingAlertCode(parseBinding({
      state: "ambiguous",
      reason: "tokens_other_account",
    })),
    "conta_ambigua",
  );
  assertEquals(
    bindingAlertCode(parseBinding({
      state: "ambiguous",
      reason: "tokens_without_account",
    })),
    "token_sem_conta",
  );
  assertEquals(bindingAlertCode(parseBinding(null)), "conta_ilegivel");
  for (const code of ["conta_ambigua", "token_sem_conta", "conta_ilegivel"]) {
    assert(/^[a-z0-9_]{1,48}$/.test(code));
  }
});

Deno.test("o dono pode desconectar com confirmação", () => {
  assertEquals(ownerMayDisconnect, true);
});

// Reserva simulada: nenhuma cobrança, nenhuma chamada à PagBank. Só mostra que
// o split de R$ 100,00 aponta para a conta que a casa tem no servidor.
import { fixedSplit, pagbankSplitBody, venueShareCents } from "./pagbank_rules.ts";
import { paymentBlock } from "./venue_finance.ts";

Deno.test("reserva simulada: sem conta a casa não recebe; com conta o repasse vai para ela", () => {
  const primary = "ACCO_PRIMARIA";
  const chargedCents = 10_000;
  const venueCents = venueShareCents(chargedCents, 2500);
  const venue = { status: "approved", pagbank_account_id: null as string | null };

  // Casa desconectada: a cobrança é recusada antes de qualquer split.
  assert(
    paymentBlock({ status: venue.status, walletId: venue.pagbank_account_id }) !==
      null,
  );

  // Conectou a conta nova: o servidor guarda e o split aponta para ela.
  venue.pagbank_account_id = "ACCO_NOVA_9999";
  assertEquals(
    paymentBlock({ status: venue.status, walletId: venue.pagbank_account_id }),
    null,
  );
  const split = fixedSplit({
    chargedCents,
    venueCents,
    venueAccountId: venue.pagbank_account_id,
    primaryAccountId: primary,
  });
  const receivers = pagbankSplitBody(split).receivers as {
    account: { id: string };
    amount: { value: number };
    reason: string;
  }[];
  const house = receivers.find((item) => item.reason === "Repasse da casa");
  assertEquals(house?.account.id, "ACCO_NOVA_9999");
  assertEquals(house?.amount.value, 7500);
  assertEquals(
    receivers.some((item) => item.account.id === "ACCO_ANTIGA_13CA"),
    false,
  );
  assertEquals(receivers.length, 2);
});
