import { assertEquals } from "jsr:@std/assert@1";
import { reconcilePayments } from "../_shared/reconcile_payments.ts";
import { handleReconcile } from "./index.ts";

Deno.test("a conciliação não chama provedor", async () => {
  const result = await reconcilePayments({
    rpc() {
      throw new Error("nao devia");
    },
  });
  assertEquals(result, { resolved: 0, pending: 0 });
});

function cronAdmin(calls: string[] = []) {
  const empty = { data: [] as unknown[], error: null };
  const chain = {
    select() {
      return chain;
    },
    eq() {
      return chain;
    },
    limit() {
      return Promise.resolve(empty);
    },
    maybeSingle() {
      return Promise.resolve({ data: null, error: null });
    },
  };
  return {
    rpc(name: string) {
      calls.push(name);
      if (name === "expire_unconfirmed_groups") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "release_due_scape_points") {
        return Promise.resolve({ data: true, error: null });
      }
      return Promise.resolve({ data: true, error: null });
    },
    from() {
      return chain;
    },
  };
}

Deno.test("reconcile-payments só aceita o segredo do cron", async () => {
  const secret = "segredo-reconcile-teste";
  const missing = await handleReconcile(
    new Request("https://example.test/reconcile-payments", { method: "POST" }),
    { reconcileSecret: secret },
  );
  assertEquals(missing.status, 401);
  const bearer = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { Authorization: "Bearer service-role-test" },
    }),
    { reconcileSecret: secret },
  );
  assertEquals(bearer.status, 401);
  const wrong = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": "outro" },
    }),
    { reconcileSecret: secret },
  );
  assertEquals(wrong.status, 401);
  const empty = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": secret },
    }),
    { reconcileSecret: "" },
  );
  assertEquals(empty.status, 401);
  const absent = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
    }),
    { reconcileSecret: "" },
  );
  assertEquals(absent.status, 401);
  const calls: string[] = [];
  const accepted = await handleReconcile(
    new Request("https://example.test/reconcile-payments", {
      method: "POST",
      headers: { "x-reconcile-secret": secret },
    }),
    {
      reconcileSecret: secret,
      admin: cronAdmin(calls),
    },
  );
  assertEquals(accepted.status, 200);
  assertEquals(await accepted.json(), { resolved: 0, pending: 0 });
  assertEquals(calls.includes("expire_unconfirmed_groups"), true);
  assertEquals(calls.includes("release_due_scape_points"), true);
});
