import { assertEquals } from "jsr:@std/assert@1";
import { chargeAsksNewCard, playerCpfDigits } from "./player_cpf.ts";

const cpf = "52998224725";

Deno.test("cpf válido passa e o inválido não", () => {
  assertEquals(playerCpfDigits("529.982.247-25"), cpf);
  assertEquals(playerCpfDigits(cpf), cpf);
  assertEquals(playerCpfDigits("111.111.111-11"), null);
  assertEquals(playerCpfDigits("52998224724"), null);
  assertEquals(playerCpfDigits("123"), null);
  assertEquals(playerCpfDigits(null), null);
  assertEquals(chargeAsksNewCard("cus_old", "card-1"), true);
  assertEquals(chargeAsksNewCard(null, "card-1"), false);
});
