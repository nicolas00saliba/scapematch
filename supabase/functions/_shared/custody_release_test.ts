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
  clock?: string | {
    startsAt?: string;
    cancelledAt?: string | null;
    sessionId?: string | null;
    session?: { starts_at: string | null; cancelled_at: string | null } | null;
    confirmedAt?: string | null;
    closesAt?: string;
    joinedAt?: string[];
  },
) {
  const updates: Record<string, unknown>[] = [];
  const options = typeof clock === "string" ? { startsAt: clock } : clock;
  const startsAt = options?.startsAt ?? "2020-01-01T00:00:00Z";
  const sessionId = options?.sessionId ?? null;
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
        lte() {
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
                id: chargeId,
                group_id: groupId,
                venue_id: "33333333-3333-4333-8333-333333333333",
                status: "paid",
              },
              error: null,
            });
          }
          if (table === "room_sessions") {
            return Promise.resolve({
              data: options?.session ?? null,
              error: null,
            });
          }
          return Promise.resolve({
            data: {
              cancelled_at: options?.cancelledAt ?? null,
              confirmed_at: options && "confirmedAt" in options
                ? options.confirmedAt
                : "2026-11-06T10:00:00Z",
              closed_at: null,
              closes_at: options?.closesAt ?? "2099-01-01T00:00:00Z",
              starts_at: startsAt,
              session_id: sessionId,
              total_spots: 4,
              minimum_spots: 2,
            },
            error: null,
          });
        },
        then(resolve: (value: unknown) => void) {
          if (table === "group_members" && options?.joinedAt) {
            resolve({
              data: options.joinedAt.map((joined_at) => ({ joined_at })),
              error: null,
              count: options.joinedAt.length,
            });
            return;
          }
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

Deno.test("cartão capturado depois do horário solta a custódia", async () => {
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

Deno.test("antes do horário a custódia fica retida e o split fica gravado", async () => {
  const releases: string[] = [];
  const admin = adminFor([], { startsAt: "2099-01-01T00:00:00Z" });
  const client = {
    releaseCustody: (splitId: string) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  };
  await finishCapturedCard({
    admin,
    pagbank: client,
    chargeId,
    splitId: "SPLI_CARD",
    paid: true,
  });
  await releasePaidIfClosed({
    admin,
    pagbank: client,
    charge: { id: chargeId, group_id: groupId, provider_split_id: "SPLI_PIX" },
    groupClosed: true,
  });
  const waiting = adminFor([{
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_WAIT",
    status: "paid",
    custody_released_at: null,
  }], { startsAt: "2099-01-01T00:00:00Z" });
  const count = await retryPendingCustodyReleases(waiting, client);
  assertEquals(releases, []);
  assertEquals(count, 0);
  assertEquals(admin.updates[0].provider_split_id, "SPLI_CARD");
  assertEquals(
    admin.updates.some((item) => "custody_release_attempts" in item),
    false,
  );
});

Deno.test("grupo cancelado não solta a custódia mesmo depois do horário", async () => {
  const releases: string[] = [];
  const admin = adminFor([{
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_CANCEL",
    status: "paid",
    custody_released_at: null,
  }], { cancelledAt: "2026-11-06T11:00:00Z" });
  const client = {
    releaseCustody: (splitId: string) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  };
  const count = await retryPendingCustodyReleases(admin, client);
  const direct = await releaseHeldSplit(admin, client, {
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_CANCEL",
    status: "paid",
  });
  assertEquals(count, 0);
  assertEquals(direct, false);
  assertEquals(releases, []);
});

Deno.test("mínimo no prazo sem confirmed_at solta a custódia", async () => {
  const releases: string[] = [];
  const admin = adminFor([], {
    confirmedAt: null,
    closesAt: "2026-11-01T12:00:00Z",
    joinedAt: ["2026-10-01T12:00:00Z", "2026-10-20T12:00:00Z"],
  });
  const ok = await releaseHeldSplit(admin, {
    releaseCustody: (splitId) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  }, {
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_PRAZO",
    status: "paid",
  });
  assertEquals(ok, true);
  assertEquals(releases, ["SPLI_PRAZO"]);
});

Deno.test("mínimo depois do prazo não solta e alerta", async () => {
  const lines: string[] = [];
  const original = console.error;
  console.error = (line?: unknown) => {
    lines.push(String(line ?? ""));
  };
  try {
    const releases: string[] = [];
    const admin = adminFor([], {
      confirmedAt: null,
      closesAt: "2026-11-01T12:00:00Z",
      joinedAt: ["2026-10-01T12:00:00Z", "2026-11-02T12:00:00Z"],
    });
    const ok = await releaseHeldSplit(admin, {
      releaseCustody: (splitId) => {
        releases.push(splitId);
        return Promise.resolve();
      },
      accountId: () => "ACCO_PRIMARY",
    }, {
      id: chargeId,
      group_id: groupId,
      provider_split_id: "SPLI_TARDE",
      status: "paid",
    });
    assertEquals(ok, false);
    assertEquals(releases, []);
    assertEquals(admin.updates.length, 0);
    assert(lines.some((line) =>
      line.includes('"scope":"pagbank-custody"') &&
      line.includes('"code":"unconfirmed_held"')
    ));
  } finally {
    console.error = original;
  }
});

Deno.test("sessão cancelada não solta a custódia", async () => {
  const releases: string[] = [];
  const admin = adminFor([], {
    sessionId: "55555555-5555-4555-8555-555555555555",
    session: {
      starts_at: "2020-01-01T00:00:00Z",
      cancelled_at: "2020-01-01T01:00:00Z",
    },
  });
  const ok = await releaseHeldSplit(admin, {
    releaseCustody: (splitId) => {
      releases.push(splitId);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  }, {
    id: chargeId,
    group_id: groupId,
    provider_split_id: "SPLI_SESSAO",
    status: "paid",
  });
  assertEquals(ok, false);
  assertEquals(releases, []);
});

Deno.test("Pix pago depois da confirmação e do horário solta a custódia e o aberto não", async () => {
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

Deno.test("conta ambígua entre casa e token: a custódia não solta e não gasta tentativa", async () => {
  const original = console.error;
  const logs: string[] = [];
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    for (
      const binding of [
        { state: "ambiguous", reason: "tokens_other_account" },
        "ilegivel",
      ]
    ) {
      const releases: string[] = [];
      const admin = Object.assign(adminFor([]), {
        rpc(fn: string) {
          if (fn === "venue_pagbank_binding") {
            return Promise.resolve({ data: binding, error: null });
          }
          return Promise.resolve({ data: true, error: null });
        },
      });
      const released = await releaseHeldSplit(admin, {
        releaseCustody: (splitId: string) => {
          releases.push(splitId);
          return Promise.resolve();
        },
        accountId: () => "ACCO_PRIMARY",
      }, {
        id: chargeId,
        group_id: groupId,
        venue_id: "33333333-3333-4333-8333-333333333333",
        provider_split_id: "SPLI_X",
      });
      assertEquals(released, false);
      assertEquals(releases, []);
      assertEquals(admin.updates, []);
    }
    assert(logs.some((line) => line.includes("conta_ambigua")));
    assert(logs.some((line) => line.includes("conta_ilegivel")));
  } finally {
    console.error = original;
  }
});

Deno.test("conta única conferida solta a custódia", async () => {
  const releases: string[] = [];
  const admin = Object.assign(adminFor([]), {
    rpc(fn: string) {
      if (fn === "venue_pagbank_binding") {
        return Promise.resolve({ data: { state: "ok" }, error: null });
      }
      return Promise.resolve({ data: true, error: null });
    },
  });
  const released = await releaseHeldSplit(admin, {
    releaseCustody: (splitId: string, accounts: string[]) => {
      releases.push(`${splitId}:${accounts[0]}`);
      return Promise.resolve();
    },
    accountId: () => "ACCO_PRIMARY",
  }, {
    id: chargeId,
    group_id: groupId,
    venue_id: "33333333-3333-4333-8333-333333333333",
    provider_split_id: "SPLI_X",
  });
  assertEquals(released, true);
  assertEquals(releases, ["SPLI_X:ACCO_VENUE"]);
});
