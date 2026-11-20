import { assertEquals } from "jsr:@std/assert@1";
import { settleGroup } from "./settle_group.ts";

Deno.test("cobrança asaas autorizada não é capturada", async () => {
  const calls: string[] = [];
  const admin = {
    from(table: string) {
      return {
        select() {
          return {
            eq() {
              return {
                eq() {
                  return this;
                },
                maybeSingle() {
                  if (table === "groups") {
                    return Promise.resolve({
                      data: {
                        id: "g1",
                        cancelled_at: null,
                        confirmed_at: "2026-11-20T12:00:00.000Z",
                        closed_at: null,
                        closes_at: null,
                        starts_at: "2026-11-20T18:00:00.000Z",
                        total_spots: 4,
                        minimum_spots: 2,
                      },
                    });
                  }
                  return Promise.resolve({ data: null });
                },
                neq() {
                  return Promise.resolve({ count: 2 });
                },
              };
            },
          };
        },
        update() {
          calls.push("update");
          return { eq: () => ({ is: () => ({ is: () => Promise.resolve({}) }) }) };
        },
      };
    },
    rpc() {
      calls.push("rpc");
      return Promise.resolve({ data: null, error: null });
    },
  };
  const charges = {
    from(table: string) {
      if (table === "payment_charges") {
        return {
          select() {
            return {
              eq: () => Promise.resolve({
                data: [{
                  id: "c1",
                  status: "authorized",
                  provider: "asaas",
                  provider_ref: "pay_old",
                  billing_type: "CREDIT_CARD",
                }],
              }),
            };
          },
        };
      }
      return admin.from(table);
    },
    rpc: admin.rpc,
  };
  await settleGroup(charges as never, "g1");
  assertEquals(calls.includes("rpc"), false);
});
