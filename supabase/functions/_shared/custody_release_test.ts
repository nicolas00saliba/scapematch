import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  finishCapturedCard,
  maxCustodyReleaseAttempts,
  releaseHeldSplit,
  releasePaidIfClosed,
  retryPendingCustodyReleases,
} from "./custody_release.ts";

const chargeId = "44444444-4444-4444-8444-444444444444";
const groupId = "11111111-1111-4111-8111-111111111111";

function adminFor(
  rows: Record<string, unknown>[],
  startsAt = "2020-01-01T00:00:00Z",
) {
  const updates: Record<string, unknown>[] = [];
  return {
    updates,
    from(table: string) {
      const self = {
        select() {
          return self;
        },
        update(values: Record<string, unknown>) {
          if (table === "payment_charges") updates.push(values);
          return self;
        },
        eq() {
          return self;
        },
        is() {
          return self;
        },
        not() {
          return self;
        },
        neq() {
          return self;
        },
        limit() {
          return self;
        },
        order() {
          return self;
        },
        or() {
          return self;
        },
        maybeSingle() {
          if (table === "venues") {
            return Promise.resolve({
              data: { pagbank_account_id: "ACCO_VENUE" },
              error: null,
            });
          }
          if (table === "payment_charges") {
            return Promise.resolve({
              data: rows[0] ?? {
                venue_id: "33333333-3333-4333-8333-333333333333",
                group_id: groupId,
              },
              error: null,
            });
          }
          return Promise.resolve({
            data: {
              cancelled_at: null,
              confirmed_at: "2026-11-06T10:00:00Z",
              closed_at: null,
              closes_at: "2099-01-01T00:00:00Z",
              starts_at: startsAt,
              total_spots: 4,
              minimum_spots: 2,
            },
            error: null,
          });
        },
        then(resolve: (value: unknown) => void) {
          resolve({
            data: table === "payment_charges" ? rows : null,
            error: null,
            count: 4,
          });
        },
      };
      return self;
    },
  };
}

Deno.test("cartão capturado com o grupo confirmado solta a custódia", async () => {
  const releases: string[] = [];
  const admin = adminFor([]);
  await finishCapturedCard({
    admin,
    pagbank: {
      releaseCustody: (splitId, accounts) => {
        releases.push(`${splitId}:${accounts.join(",")}`);
        return Promise.resolve();
      },
      accountId: () => "ACCO_PRIMARY",
    },
    chargeId,
    splitId: "SPLI_CARD",
    paid: true,
  });
  assertEquals(releases, ["SPLI_CARD:ACCO_VENUE,ACCO_PRIMARY"]);
  assertEquals(admin.updates[0].provider_split_id, "SPLI_CARD");
  assert(typeof admin.updates[1].custody_released_at === "string");
  assertEquals(admin.updates[1].custody_release_failed_at, null);
});

Deno.test("falha ao soltar a custódia fica registrada para o cron", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    const admin = adminFor([]);
    const ok = await finishCapturedCard({
      admin,
      pagbank: {
        releaseCustody: () => Promise.reject(new Error("PagBank 500: indisponivel")),
        accountId: () => "ACCO_PRIMARY",
      },
      chargeId,
      splitId: "SPLI_CARD",
      paid: true,
    });
    assertEquals(ok, undefined);
    assertEquals(
      admin.updates.some((item) => "custody_release_failed_at" in item),
      true,
    );
    assertEquals(
      admin.updates.some((item) => item.custody_released_at),
      false,
    );
    assert(logs.some((line) => line.includes("custody_release_failed")));
  } finally {
    console.error = original;
  }
});

Deno.test("Pix pago depois da confirmação solta a custódia e o aberto não", async () => {
  const releases: string[] = [];
  const client = {
    releaseCustody: (splitId: string) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  };
  const closed = adminFor([]);
  await releasePaidIfClosed({
    admin: closed,
    pagbank: client,
    charge: { id: chargeId, provider_split_id: "SPLI_PIX" },
    groupClosed: true,
  });
  const open = adminFor([]);
  await releasePaidIfClosed({
    admin: open,
    pagbank: client,
    charge: { id: chargeId, provider_split_id: "SPLI_PIX" },
    groupClosed: false,
  });
  assertEquals(releases, ["SPLI_PIX"]);
  assertEquals(open.updates.length, 0);
});

Deno.test("o cron repete a custódia que falhou", async () => {
  const releases: string[] = [];
  const admin = adminFor([{
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_RETRY",
    status: "paid",
    custody_released_at: null,
  }]);
  const count = await retryPendingCustodyReleases(admin, {
    releaseCustody: (splitId) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  });
  assertEquals(count, 1);
  assertEquals(releases, ["SPLI_RETRY"]);
});

Deno.test("custódia não sai antes do horário da sessão", async () => {
  const releases: string[] = [];
  const admin = adminFor([], "2099-01-01T00:00:00Z");
  const ok = await releaseHeldSplit(admin, {
    releaseCustody: (splitId) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  }, {
    id: chargeId,
    provider_split_id: "SPLI_CEDO",
  });
  assertEquals(ok, false);
  assertEquals(releases, []);
  assertEquals(admin.updates.length, 0);
});

Deno.test("a custódia para depois do limite e alerta", async () => {
  const lines: string[] = [];
  const original = console.error;
  console.error = (line?: unknown) => {
    lines.push(String(line ?? ""));
  };
  try {
    const admin = adminFor([]);
    const ok = await releaseHeldSplit(admin, {
      releaseCustody: () => Promise.reject(new Error("PagBank 500: indisponivel")),
      accountId: () => "ACCO_PRIMARY",
    }, {
      id: chargeId,
      provider_split_id: "SPLI_CARD",
      custody_release_attempts: maxCustodyReleaseAttempts - 1,
    });
    assertEquals(ok, false);
    const last = admin.updates.at(-1);
    assertEquals(last?.custody_release_attempts, maxCustodyReleaseAttempts);
    assert(lines.some((line) => line.includes("custody_release_exhausted")));
  } finally {
    console.error = original;
  }
});

Deno.test("create-charge e o webhook usam a liberação da custódia", async () => {
  const charge = await Deno.readTextFile(
    new URL("../create-charge/index.ts", import.meta.url),
  );
  const webhook = await Deno.readTextFile(
    new URL("./charge_notice.ts", import.meta.url),
  );
  const settle = await Deno.readTextFile(
    new URL("../settle-charges/index.ts", import.meta.url),
  );
  const reconcile = await Deno.readTextFile(
    new URL("../reconcile-payments/index.ts", import.meta.url),
  );
  assert(charge.includes("finishCapturedCard"));
  assert(charge.includes("releasePaidIfClosed"));
  assert(webhook.includes("releasePaidIfClosed"));
  assert(settle.includes("retryPendingCustodyReleases"));
  assert(reconcile.includes("retryPendingCustodyReleases"));
});
