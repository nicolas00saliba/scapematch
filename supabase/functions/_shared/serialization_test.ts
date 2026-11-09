import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  DbRpcError,
  isSerializationConflict,
  retrySerialization,
} from "./serialization.ts";

Deno.test("55P03 e 40001 são conflito serializável", () => {
  assertEquals(isSerializationConflict(new DbRpcError("55P03")), true);
  assertEquals(isSerializationConflict(new DbRpcError("40001")), true);
  assertEquals(
    isSerializationConflict(new Error("canceling statement due to lock timeout")),
    true,
  );
  assertEquals(isSerializationConflict(new DbRpcError("23505")), false);
});

Deno.test("a retentativa para no sucesso e não repete erro comum", async () => {
  let calls = 0;
  const value = await retrySerialization(async () => {
    calls += 1;
    if (calls < 3) throw new DbRpcError("55P03");
    return "ok";
  });
  assertEquals(value, "ok");
  assertEquals(calls, 3);

  let other = 0;
  await assertRejects(
    () =>
      retrySerialization(async () => {
        other += 1;
        throw new Error("erro");
      }),
    Error,
    "erro",
  );
  assertEquals(other, 1);
});

Deno.test("depois das tentativas o lock_timeout continua sem detalhe", async () => {
  let calls = 0;
  const error = await assertRejects(
    () =>
      retrySerialization(async () => {
        calls += 1;
        throw new DbRpcError("55P03");
      }),
    DbRpcError,
    "erro",
  );
  assertEquals(calls, 3);
  assertEquals((error as DbRpcError).message, "erro");
  assertEquals((error as DbRpcError).message.includes("cents"), false);
});
