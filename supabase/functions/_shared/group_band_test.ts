import { assertEquals } from "jsr:@std/assert@1";
import { bandSettlement } from "./group_band.ts";

const past = "2026-11-01T10:00:00Z";
const future = "2099-11-01T10:00:00Z";
const now = Date.parse("2026-11-10T12:00:00Z");

Deno.test("confirma no mínimo e segue aberto até o máximo", () => {
  const group = {
    cancelled_at: null,
    confirmed_at: null,
    closed_at: null,
    closes_at: future,
    minimum_spots: 4,
    total_spots: 6,
  };
  assertEquals(bandSettlement(group, 3, now), "wait");
  assertEquals(bandSettlement(group, 4, now), "capture");
  assertEquals(
    bandSettlement({ ...group, confirmed_at: past, closed_at: null }, 5, now),
    "capture",
  );
});

Deno.test("prazo sem o mínimo libera", () => {
  const group = {
    cancelled_at: null,
    confirmed_at: null,
    closed_at: null,
    closes_at: past,
    minimum_spots: 4,
    total_spots: 6,
  };
  assertEquals(bandSettlement(group, 3, now), "release");
  assertEquals(bandSettlement(group, 4, now), "release");
  assertEquals(
    bandSettlement({ ...group, confirmed_at: past }, 5, now),
    "capture",
  );
});
