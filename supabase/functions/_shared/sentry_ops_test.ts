import { assert, assertEquals } from "jsr:@std/assert";
import { captureOpsAlert } from "./sentry_ops.ts";

const dsn = "https://publickey@o1.ingest.sentry.io/123";

Deno.test("sem DSN o alerta fica só no log e não chama a rede", async () => {
  let called = false;
  const sent = await captureOpsAlert(
    { get: () => undefined },
    () => {
      called = true;
      return Promise.resolve({ ok: true });
    },
    { scope: "schedule-venue-withdrawals", code: "venue_withdrawals_config_ausente" },
  );
  assertEquals(sent, false);
  assertEquals(called, false);
});

Deno.test("o evento do Sentry não carrega o DSN nem o valor de um segredo", async () => {
  const seen: { url: string; body: string; auth: string }[] = [];
  const sent = await captureOpsAlert(
    { get: (name) => name === "SENTRY_DSN" ? dsn : "segredo-que-nao-sai" },
    (input, init) => {
      seen.push({
        url: input,
        body: init?.body ?? "",
        auth: init?.headers?.["X-Sentry-Auth"] ?? "",
      });
      return Promise.resolve({ ok: true });
    },
    { scope: "schedule-venue-withdrawals", code: "venue_withdrawals_config_ausente" },
  );
  assertEquals(sent, true);
  assertEquals(seen.length, 1);
  assertEquals(seen[0].url, "https://o1.ingest.sentry.io/api/123/envelope/");
  assert(!seen[0].url.includes("publickey"));
  assert(!seen[0].body.includes("publickey"));
  assert(!seen[0].body.includes("segredo-que-nao-sai"));
  assert(seen[0].body.includes("venue_withdrawals_config_ausente"));
  assert(seen[0].auth.includes("sentry_key=publickey"));
});

Deno.test("DSN fora do ingest do Sentry não dispara pedido", async () => {
  let called = false;
  const sent = await captureOpsAlert(
    { get: () => "https://publickey@169.254.169.254/123" },
    () => {
      called = true;
      return Promise.resolve({ ok: true });
    },
    { scope: "ops", code: "config_ausente" },
  );
  assertEquals(sent, false);
  assertEquals(called, false);
});
