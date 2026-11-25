import { assert, assertEquals } from "jsr:@std/assert@1";
import { PagBankProvider, pagbankProductionBaseUrl } from "./pagbank_provider.ts";
import {
  pagbankNoticeRefs,
  pollPendingPagBankCharges,
} from "./charge_notice.ts";

const chargeId = "44444444-4444-4444-8444-444444444444";
const groupId = "11111111-1111-4111-8111-111111111111";

function adminFor(rows: Record<string, unknown>[]) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const chain = (table: string) => {
    const self = {
      select() {
        return self;
      },
      eq() {
        return self;
      },
      not() {
        return self;
      },
      neq() {
        return self;
      },
      order() {
        return self;
      },
      limit() {
        return self;
      },
      range() {
        return self;
      },
      update() {
        return self;
      },
      maybeSingle() {
        if (table === "venues") {
          return Promise.resolve({
            data: { pagbank_account_id: "ACCO_VENUE" },
            error: null,
          });
        }
        if (table === "groups") {
          return Promise.resolve({
            data: {
              cancelled_at: null,
              confirmed_at: "2026-11-06T10:00:00Z",
              closed_at: null,
              closes_at: "2099-01-01T00:00:00Z",
              total_spots: 4,
              minimum_spots: 2,
            },
            error: null,
          });
        }
        return Promise.resolve({
          data: { payer_document_status: "matched" },
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
  };
  return {
    calls,
    from(table: string) {
      return chain(table);
    },
    rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      if (fn === "apply_payment_transition") {
        return Promise.resolve({
          data: { status: args.p_next_status ?? "paid" },
          error: null,
        });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
}

function provider(status: string) {
  return new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    () =>
      Promise.resolve(new Response(JSON.stringify({
        id: "CHAR_PENDENTE",
        status,
        payment_method: { type: "PIX" },
      }), { status: 200 })),
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
}

const pending = {
  id: chargeId,
  group_id: groupId,
  user_id: "22222222-2222-4222-8222-222222222222",
  venue_id: "33333333-3333-4333-8333-333333333333",
  amount_cents: 500,
  commission_bps: 1000,
  status: "pending",
  billing_type: "PIX",
  provider_ref: "CHAR_PENDENTE",
  provider_split_id: "SPLI_PIX",
  custody_released_at: null,
  created_at: "2026-11-01T00:00:00Z",
};

Deno.test("Pix pendente pago no PagBank segue a lógica do webhook", async () => {
  const admin = adminFor([pending]);
  const applied = await pollPendingPagBankCharges(
    admin,
    provider("PAID"),
    { get: () => undefined },
  );
  assertEquals(applied, 1);
  const transition = admin.calls.find((call) =>
    call.fn === "apply_payment_transition"
  );
  assertEquals(transition?.args.p_charge_id, chargeId);
  assertEquals(transition?.args.p_next_status, "paid");
  assertEquals(transition?.args.p_credit, true);
});

Deno.test("Pix ainda aguardando não move a cobrança", async () => {
  const admin = adminFor([pending]);
  const applied = await pollPendingPagBankCharges(
    admin,
    provider("WAITING"),
    { get: () => undefined },
  );
  assertEquals(applied, 0);
  assertEquals(admin.calls, []);
});

Deno.test("webhook casa o pedido e o split sai do charge pago", async () => {
  assertEquals(
    pagbankNoticeRefs({
      id: "ORDE_PIX",
      charges: [{ id: "CHAR_PIX", status: "PAID" }],
    }),
    ["ORDE_PIX", "CHAR_PIX"],
  );
  const urls: string[] = [];
  const paid = {
    id: "ORDE_PIX",
    charges: [{
      id: "CHAR_PIX",
      status: "PAID",
      amount: { value: 500 },
      payment_method: { type: "PIX" },
      splits: { id: "SPLI_PAGO" },
    }],
  };
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    (url: string, init?: RequestInit) => {
      urls.push(`${init?.method ?? "GET"} ${url}`);
      if (url.includes("/custody/release")) {
        const posted = JSON.parse(String(init?.body ?? "{}"));
        assertEquals(
          posted.receivers.map((item: { account: { id: string } }) =>
            item.account.id
          ),
          ["ACCO_VENUE", "ACCO_PRIMARY"],
        );
      }
      return Promise.resolve(
        new Response(JSON.stringify(paid), { status: 200 }),
      );
    },
    () => Promise.resolve(),
    "ACCO_PRIMARY",
  );
  const row = { ...pending, provider_ref: "ORDE_PIX", provider_split_id: null };
  const admin = adminFor([row]);
  const applied = await pollPendingPagBankCharges(
    admin,
    pagbank,
    { get: () => undefined },
  );
  assertEquals(applied, 1);
  assert(urls.some((url) => url.includes("/orders/ORDE_PIX")));
  assert(urls.some((url) => url.includes("/splits/SPLI_PAGO/custody/release")));
});

Deno.test("Pix vencido sai da fila como cancelado", async () => {
  const expired = {
    id: "ORDE_VELHO",
    charges: [{
      id: "CHAR_VELHO",
      status: "WAITING",
      payment_method: {
        type: "PIX",
        pix: { expiration_date: "2020-01-01T00:00:00-03:00" },
      },
    }],
  };
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    () =>
      Promise.resolve(new Response(JSON.stringify(expired), { status: 200 })),
  );
  const row = { ...pending, provider_ref: "ORDE_VELHO" };
  const admin = adminFor([row]);
  const applied = await pollPendingPagBankCharges(
    admin,
    pagbank,
    { get: () => undefined },
  );
  assertEquals(applied, 1);
  const transition = admin.calls.find((call) =>
    call.fn === "apply_payment_transition"
  );
  assertEquals(transition?.args.p_next_status, "cancelled");
  assertEquals(transition?.args.p_credit, false);
});

Deno.test("Pix com validade futura continua pendente", async () => {
  const open = {
    id: "ORDE_NOVO",
    charges: [{
      id: "CHAR_NOVO",
      status: "WAITING",
      payment_method: {
        type: "PIX",
        pix: { expiration_date: "2099-01-01T00:00:00-03:00" },
      },
    }],
  };
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    () => Promise.resolve(new Response(JSON.stringify(open), { status: 200 })),
  );
  const admin = adminFor([{ ...pending, provider_ref: "ORDE_NOVO" }]);
  const applied = await pollPendingPagBankCharges(
    admin,
    pagbank,
    { get: () => undefined },
  );
  assertEquals(applied, 0);
  assertEquals(admin.calls, []);
});

function captureLogs(run: () => Promise<void>): Promise<string[]> {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map((item) => String(item)).join(" "));
  };
  return run().finally(() => {
    console.error = original;
  }).then(() => logs);
}

Deno.test("poll de CHAR_ usa o pedido por charge_id e segue depois do 406", async () => {
  const urls: string[] = [];
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    (url: string, init?: RequestInit) => {
      urls.push(`${init?.method ?? "GET"} ${url}`);
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("Accept"), "application/json");
      assertEquals(headers.get("Content-Type"), null);
      if (url.includes("charge_id=CHAR_PENDENTE")) {
        return Promise.resolve(new Response("Not Acceptable pb-token-secret", {
          status: 406,
        }));
      }
      return Promise.resolve(new Response(JSON.stringify({
        id: "ORDE_OK",
        charges: [{
          id: "CHAR_OK",
          status: "WAITING",
          payment_method: { type: "PIX" },
        }],
      }), { status: 200 }));
    },
  );
  const second = {
    ...pending,
    id: "55555555-5555-4555-8555-555555555555",
    provider_ref: "ORDE_OK",
  };
  const admin = adminFor([pending, second]);
  const logs = await captureLogs(async () => {
    const applied = await pollPendingPagBankCharges(
      admin,
      pagbank,
      { get: () => undefined },
    );
    assertEquals(applied, 0);
  });
  assert(urls.some((url) => url.includes("/orders?charge_id=CHAR_PENDENTE")));
  assert(urls.some((url) => url.includes("/orders/ORDE_OK")));
  assert(urls.every((url) => !url.includes("/charges/CHAR_PENDENTE")));
  assert(logs.some((line) =>
    line.includes("pending_charge_poll") && line.includes("406")
  ));
  assert(logs.every((line) => !line.includes("pb-token-secret")));
});

Deno.test("404 no poll não vira indisponibilidade e a consulta seguinte anda", async () => {
  const urls: string[] = [];
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    (url: string) => {
      urls.push(url);
      if (url.endsWith("/orders/ORDE_SUMIU")) {
        return Promise.resolve(new Response("não", { status: 404 }));
      }
      return Promise.resolve(new Response(JSON.stringify({
        id: "ORDE_OK",
        charges: [{
          id: "CHAR_OK",
          status: "WAITING",
          payment_method: { type: "PIX" },
        }],
      }), { status: 200 }));
    },
  );
  const admin = adminFor([
    { ...pending, provider_ref: "ORDE_SUMIU" },
    {
      ...pending,
      id: "55555555-5555-4555-8555-555555555555",
      provider_ref: "ORDE_OK",
    },
  ]);
  const logs = await captureLogs(async () => {
    const applied = await pollPendingPagBankCharges(
      admin,
      pagbank,
      { get: () => undefined },
    );
    assertEquals(applied, 0);
  });
  assert(urls.some((url) => url.endsWith("/orders/ORDE_SUMIU")));
  assert(urls.some((url) => url.endsWith("/orders/ORDE_OK")));
  assert(logs.every((line) => !line.includes("pagbank_unavailable")));
});

Deno.test("timeout no poll registra 408 sem o token", async () => {
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    () => Promise.reject(new DOMException("The signal has been aborted", "TimeoutError")),
  );
  const admin = adminFor([{ ...pending, provider_ref: "ORDE_LENTO" }]);
  const logs = await captureLogs(async () => {
    const applied = await pollPendingPagBankCharges(
      admin,
      pagbank,
      { get: () => undefined },
    );
    assertEquals(applied, 0);
  });
  assert(logs.some((line) =>
    line.includes("pending_charge_poll") && line.includes("408")
  ));
  assert(logs.every((line) => !line.includes("pb-token-secret")));
});

Deno.test("poll pagina por cursor e não pula pendente que andou na fila", async () => {
  const rows = Array.from({ length: 21 }, (_, index) => ({
    ...pending,
    id: `44444444-4444-4444-8444-${String(index).padStart(12, "0")}`,
    provider_ref: `ORDE_${index}`,
    created_at: index >= 19
      ? "2026-11-01T00:19:00.000Z"
      : `2026-11-01T00:${String(index).padStart(2, "0")}:00.000Z`,
  }));
  const pendingRows = rows.map((row) => ({ ...row }));
  const urls: string[] = [];
  const filters: string[] = [];
  const ranges: number[] = [];
  const chain = (table: string) => {
    let cursor = "";
    let pageLimit = pendingRows.length;
    let start = -1;
    let end = -1;
    const self = {
      select() {
        return self;
      },
      eq() {
        return self;
      },
      not() {
        return self;
      },
      neq() {
        return self;
      },
      order() {
        return self;
      },
      limit(count: number) {
        pageLimit = count;
        return self;
      },
      or(filter: string) {
        cursor = filter;
        if (table === "payment_charges") filters.push(filter);
        return self;
      },
      range(from: number, to: number) {
        start = from;
        end = to;
        if (table === "payment_charges") ranges.push(from);
        return self;
      },
      maybeSingle() {
        return Promise.resolve({ data: null, error: null });
      },
      then(resolve: (value: unknown) => void) {
        const sorted = pendingRows
          .filter((row) => row.status === "pending")
          .sort((left, right) =>
            left.created_at === right.created_at
              ? left.id < right.id ? -1 : left.id > right.id ? 1 : 0
              : left.created_at < right.created_at ? -1 : 1
          );
        const window = start >= 0
          ? sorted.slice(start, end + 1)
          : (cursor ? sorted.filter((row) => pastCursor(cursor, row)) : sorted)
            .slice(0, pageLimit);
        start = -1;
        end = -1;
        cursor = "";
        const data = table === "payment_charges" ? window : [];
        resolve({ data, error: null, count: data.length });
      },
    };
    return self;
  };
  const admin = {
    from: (table: string) => chain(table),
    rpc() {
      return Promise.resolve({ data: [], error: null });
    },
  };
  const pagbank = new PagBankProvider(
    "pb-token-secret",
    pagbankProductionBaseUrl,
    (url: string) => {
      urls.push(url);
      if (url.endsWith("/orders/ORDE_0")) {
        const row = pendingRows.find((item) => item.provider_ref === "ORDE_0");
        if (row) row.status = "paid";
      }
      return Promise.resolve(new Response(JSON.stringify({
        id: "ORDE_PAGINA",
        charges: [{
          id: "CHAR_PAGINA",
          status: "WAITING",
          payment_method: { type: "PIX" },
        }],
      }), { status: 200 }));
    },
  );
  const applied = await pollPendingPagBankCharges(
    admin,
    pagbank,
    { get: () => undefined },
  );
  assertEquals(applied, 0);
  assertEquals(ranges, []);
  assertEquals(urls.length, 21);
  assert(urls.every((url) => url.includes("/orders/ORDE_")));
  assertEquals(filters.length, 1);
  assert(filters[0].includes("2026-11-01T00:19:00.000Z"));
  assert(filters[0].includes(rows[19].id));
  assert(filters[0].includes("id.gt"));
});

function pastCursor(
  filter: string,
  row: { created_at: string; id: string },
): boolean {
  const match = filter.match(
    /created_at\.gt\.(?:"([^"]+)"|([^,]+)),and\(created_at\.eq\.(?:"([^"]+)"|([^,]+)),id\.gt\.(?:"([^"]+)"|([^)]+))\)/,
  );
  if (!match) return false;
  const createdAt = match[1] ?? match[2];
  const id = match[5] ?? match[6];
  if (row.created_at > createdAt) return true;
  return row.created_at === createdAt && row.id > id;
}
